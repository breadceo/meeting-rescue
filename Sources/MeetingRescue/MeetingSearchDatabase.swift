import Foundation
import MeetingRescueCore
import SQLite3

struct MeetingSearchDatabaseResult: Equatable, Sendable {
    var path: String
    var match: MeetingHistorySearchMatch
}

final class MeetingSearchDatabase: @unchecked Sendable {
    private let schemaVersion = "2"
    private let databaseURL: URL

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func storedSignature() throws -> String? {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try createSchema(in: db)
        guard try scalarString(in: db, sql: "SELECT value FROM metadata WHERE key = 'schemaVersion' LIMIT 1") == schemaVersion else {
            return nil
        }
        return try scalarString(
            in: db,
            sql: "SELECT value FROM metadata WHERE key = 'signature' LIMIT 1"
        )
    }

    func rebuild(
        items: [MeetingHistoryItem],
        signature: String,
        progress: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
    ) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try createSchema(in: db)
        try execute("BEGIN IMMEDIATE TRANSACTION", in: db)
        do {
            try execute("DELETE FROM segments_fts", in: db)
            try execute("DELETE FROM segments_semantic", in: db)
            let total = max(items.count, 1)
            progress?(0, total)
            for (index, item) in items.enumerated() {
                try insert(item: item, in: db)
                progress?(index + 1, total)
            }
            try upsertMetadata(key: "schemaVersion", value: schemaVersion, in: db)
            try upsertMetadata(key: "semanticProvider", value: MeetingHistorySearch.semanticProviderName, in: db)
            try upsertMetadata(key: "semanticEstimatedCostUSD", value: "0", in: db)
            try upsertMetadata(key: "signature", value: signature, in: db)
            try upsertMetadata(key: "updatedAt", value: ISO8601DateFormatter().string(from: Date()), in: db)
            try execute("COMMIT", in: db)
        } catch {
            try? execute("ROLLBACK", in: db)
            throw error
        }
    }

    func search(query: String, limit: Int = 240) throws -> [MeetingSearchDatabaseResult] {
        let startedAt = Date()
        let terms = MeetingHistorySearch.indexQueryTerms(for: query)
        guard !terms.isEmpty else {
            return []
        }

        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try createSchema(in: db)
        var bestByPath: [String: MeetingSearchDatabaseResult] = [:]
        try keywordSearch(query: query, terms: terms, limit: limit, db: db, bestByPath: &bestByPath)
        try semanticSearch(query: query, limit: limit, db: db, bestByPath: &bestByPath)
        try upsertMetadata(key: "lastSearchDiagnostics", value: searchDiagnosticsJSON(query: query, startedAt: startedAt), in: db)
        return bestByPath.values.sorted {
            if $0.match.score == $1.match.score {
                return $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
            return $0.match.score > $1.match.score
        }
    }

    private func keywordSearch(
        query: String,
        terms: [String],
        limit: Int,
        db: OpaquePointer,
        bestByPath: inout [String: MeetingSearchDatabaseResult]
    ) throws {
        let matchQuery = terms.map(escapedFTSTerm).joined(separator: " ")
        let sql = """
        SELECT path, field, timestamp, text, weight, bm25(segments_fts) AS rank
        FROM segments_fts
        WHERE segments_fts MATCH ?
        ORDER BY rank ASC
        LIMIT ?;
        """
        let statement = try prepare(sql, in: db)
        defer { sqlite3_finalize(statement) }
        bindText(matchQuery, at: 1, in: statement)
        sqlite3_bind_int(statement, 2, Int32(limit))

        while sqlite3_step(statement) == SQLITE_ROW {
            guard !Task.isCancelled else {
                return
            }
            let path = columnText(statement, 0)
            let field = MeetingHistorySearchField(rawValue: columnText(statement, 1)) ?? .rawTranscript
            let timestamp = optionalColumnText(statement, 2)
            let text = columnText(statement, 3)
            let weight = Int(sqlite3_column_int(statement, 4))
            let rank = sqlite3_column_double(statement, 5)
            let score = weight + max(1, Int((-rank * 100).rounded()))
            let match = MeetingHistorySearchMatch(
                score: score,
                field: field,
                snippet: text.trimmedFTSSnippet(),
                timestamp: timestamp
            )
            let result = MeetingSearchDatabaseResult(path: path, match: match)
            if let existing = bestByPath[path], existing.match.score >= score {
                continue
            }
            bestByPath[path] = result
        }
    }

    private func semanticSearch(
        query: String,
        limit: Int,
        db: OpaquePointer,
        bestByPath: inout [String: MeetingSearchDatabaseResult]
    ) throws {
        let queryVector = MeetingHistorySearch.semanticVector(for: query)
        guard !queryVector.isEmpty else {
            return
        }
        let sql = """
        SELECT path, field, timestamp, text, weight, vector
        FROM segments_semantic;
        """
        let statement = try prepare(sql, in: db)
        defer { sqlite3_finalize(statement) }

        var bestSemanticByPath: [String: MeetingSearchDatabaseResult] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard !Task.isCancelled else {
                return
            }
            let vector = columnText(statement, 5)
            let semanticScore = MeetingHistorySearch.semanticScore(queryVector: queryVector, vectorString: vector)
            guard semanticScore > 0 else {
                continue
            }
            let path = columnText(statement, 0)
            let field = MeetingHistorySearchField(rawValue: columnText(statement, 1)) ?? .rawTranscript
            let timestamp = optionalColumnText(statement, 2)
            let text = columnText(statement, 3)
            let weight = Int(sqlite3_column_int(statement, 4))
            let score = weight + semanticScore
            let match = MeetingHistorySearchMatch(
                score: score,
                field: field,
                snippet: text.trimmedFTSSnippet(),
                timestamp: timestamp
            )
            let result = MeetingSearchDatabaseResult(path: path, match: match)
            if let existing = bestSemanticByPath[path], existing.match.score >= score {
                continue
            }
            bestSemanticByPath[path] = result
        }

        let semanticResults = bestSemanticByPath.values.sorted {
            if $0.match.score == $1.match.score {
                return $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
            return $0.match.score > $1.match.score
        }
        .prefix(limit)

        for result in semanticResults {
            if let existing = bestByPath[result.path], existing.match.score >= result.match.score {
                continue
            }
            bestByPath[result.path] = result
        }
    }

    private func openDatabase() throws -> OpaquePointer {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            throw error(db, fallback: "SQLite database를 열 수 없습니다.")
        }
        return db
    }

    private func createSchema(in db: OpaquePointer) throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """, in: db)
        try execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS segments_fts USING fts5(
            path UNINDEXED,
            field UNINDEXED,
            timestamp UNINDEXED,
            text UNINDEXED,
            weight UNINDEXED,
            indexedText,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """, in: db)
        try execute("""
        CREATE TABLE IF NOT EXISTS segments_semantic (
            path TEXT NOT NULL,
            field TEXT NOT NULL,
            timestamp TEXT,
            text TEXT NOT NULL,
            weight INTEGER NOT NULL,
            vector TEXT NOT NULL
        );
        """, in: db)
        try execute("""
        CREATE INDEX IF NOT EXISTS idx_segments_semantic_path
        ON segments_semantic(path);
        """, in: db)
    }

    private func insert(item: MeetingHistoryItem, in db: OpaquePointer) throws {
        let ftsSQL = """
        INSERT INTO segments_fts(path, field, timestamp, text, weight, indexedText)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        let ftsStatement = try prepare(ftsSQL, in: db)
        defer { sqlite3_finalize(ftsStatement) }

        let semanticSQL = """
        INSERT INTO segments_semantic(path, field, timestamp, text, weight, vector)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        let semanticStatement = try prepare(semanticSQL, in: db)
        defer { sqlite3_finalize(semanticStatement) }

        for section in item.searchSections {
            sqlite3_reset(ftsStatement)
            sqlite3_clear_bindings(ftsStatement)
            bindText(item.url.path, at: 1, in: ftsStatement)
            bindText(section.field.rawValue, at: 2, in: ftsStatement)
            bindOptionalText(section.timestamp, at: 3, in: ftsStatement)
            bindText(section.text, at: 4, in: ftsStatement)
            bindText(String(section.weight), at: 5, in: ftsStatement)
            bindText(MeetingHistorySearch.indexText(for: section.text), at: 6, in: ftsStatement)
            guard sqlite3_step(ftsStatement) == SQLITE_DONE else {
                throw error(db, fallback: "검색 segment 저장에 실패했습니다.")
            }

            let vector = MeetingHistorySearch.semanticVectorString(for: section.text)
            guard !vector.isEmpty else {
                continue
            }
            sqlite3_reset(semanticStatement)
            sqlite3_clear_bindings(semanticStatement)
            bindText(item.url.path, at: 1, in: semanticStatement)
            bindText(section.field.rawValue, at: 2, in: semanticStatement)
            bindOptionalText(section.timestamp, at: 3, in: semanticStatement)
            bindText(section.text, at: 4, in: semanticStatement)
            bindText(String(section.weight), at: 5, in: semanticStatement)
            bindText(vector, at: 6, in: semanticStatement)
            guard sqlite3_step(semanticStatement) == SQLITE_DONE else {
                throw error(db, fallback: "검색 semantic segment 저장에 실패했습니다.")
            }
        }
    }

    private func upsertMetadata(key: String, value: String, in db: OpaquePointer) throws {
        let statement = try prepare(
            "INSERT INTO metadata(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            in: db
        )
        defer { sqlite3_finalize(statement) }
        bindText(key, at: 1, in: statement)
        bindText(value, at: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw error(db, fallback: "검색 metadata 저장에 실패했습니다.")
        }
    }

    private func scalarString(in db: OpaquePointer, sql: String) throws -> String? {
        let statement = try prepare(sql, in: db)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return optionalColumnText(statement, 0)
    }

    private func execute(_ sql: String, in db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(errorMessage) }
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
            throw SearchDatabaseError(message ?? "SQLite statement 실행에 실패했습니다.")
        }
    }

    private func prepare(_ sql: String, in db: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw error(db, fallback: "SQLite statement 준비에 실패했습니다.")
        }
        return statement
    }

    private func bindText(_ value: String, at index: Int32, in statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bindOptionalText(_ value: String?, at index: Int32, in statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bindText(value, at: index, in: statement)
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String {
        optionalColumnText(statement, index) ?? ""
    }

    private func optionalColumnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    private func escapedFTSTerm(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func searchDiagnosticsJSON(query: String, startedAt: Date) -> String {
        let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
        let escapedQuery = query.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {"query":"\(escapedQuery)","provider":"\(MeetingHistorySearch.semanticProviderName)","estimatedCostUSD":0,"elapsedMilliseconds":\(elapsedMilliseconds)}
        """
    }

    private func error(_ db: OpaquePointer?, fallback: String) -> SearchDatabaseError {
        if let db, let message = sqlite3_errmsg(db) {
            return SearchDatabaseError(String(cString: message))
        }
        return SearchDatabaseError(fallback)
    }
}

private struct SearchDatabaseError: Error, LocalizedError {
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension String {
    func trimmedFTSSnippet(limit: Int = 96) -> String {
        let oneLine = components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard oneLine.count > limit else {
            return oneLine
        }
        return String(oneLine.prefix(limit - 1)) + "…"
    }
}
