import Foundation

public enum TranscriptTextEncodingKind: Equatable, Sendable {
    case utf8
    case utf16LittleEndian
    case utf16BigEndian
}

public struct TranscriptUTF8PrefixDecodeResult: Equatable, Sendable {
    public let text: String
    public let pendingData: Data

    public init(text: String, pendingData: Data) {
        self.text = text
        self.pendingData = pendingData
    }
}

public struct TranscriptIncrementalTextDecoder: Equatable, Sendable {
    private var pendingData = Data()

    public init() {}

    public var pendingByteCount: Int {
        pendingData.count
    }

    public mutating func reset() {
        pendingData = Data()
    }

    public mutating func decode(_ data: Data) -> String {
        guard !data.isEmpty || !pendingData.isEmpty else {
            return ""
        }

        var combined = pendingData
        combined.append(data)
        let result = TranscriptTextDecoder.decodeUTF8Prefix(combined)
        pendingData = result.pendingData
        return result.text
    }
}

public enum TranscriptTextDecoder {
    public static func decode(_ data: Data) -> String {
        guard !data.isEmpty else {
            return ""
        }

        switch encodingKind(for: data) {
        case .utf16LittleEndian:
            return String(data: data, encoding: .utf16LittleEndian) ?? String(decoding: data, as: UTF8.self)
        case .utf16BigEndian:
            return String(data: data, encoding: .utf16BigEndian) ?? String(decoding: data, as: UTF8.self)
        case .utf8:
            return decodeUTF8Prefix(data).text
        }
    }

    public static func encodingKind(for data: Data) -> TranscriptTextEncodingKind {
        if data.starts(with: [0xFF, 0xFE]) {
            return .utf16LittleEndian
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return .utf16BigEndian
        }
        if likelyUTF16(data) {
            return .utf16LittleEndian
        }
        return .utf8
    }

    public static func decodeUTF8Prefix(_ data: Data) -> TranscriptUTF8PrefixDecodeResult {
        guard !data.isEmpty else {
            return TranscriptUTF8PrefixDecodeResult(text: "", pendingData: Data())
        }
        guard !data.hasDominantLeadingNULPrefix() else {
            return TranscriptUTF8PrefixDecodeResult(text: "", pendingData: Data())
        }

        let maxPendingCount = min(3, data.count)
        for pendingCount in 0...maxPendingCount {
            let validCount = data.count - pendingCount
            let prefix = Data(data.prefix(validCount))
            guard let text = String(data: prefix, encoding: .utf8) else {
                continue
            }
            return TranscriptUTF8PrefixDecodeResult(
                text: text,
                pendingData: Data(data.suffix(pendingCount))
            )
        }

        return TranscriptUTF8PrefixDecodeResult(
            text: String(decoding: data, as: UTF8.self),
            pendingData: Data()
        )
    }

    private static func likelyUTF16(_ data: Data) -> Bool {
        let sample = data.prefix(200)
        guard sample.count >= 8 else {
            return false
        }
        guard sample.contains(where: { $0 != 0 }) else {
            return false
        }
        let zeroCount = sample.filter { $0 == 0 }.count
        guard Double(zeroCount) / Double(sample.count) > 0.20 else {
            return false
        }

        var evenTotal = 0
        var oddTotal = 0
        var evenZeroCount = 0
        var oddZeroCount = 0
        for (index, byte) in sample.enumerated() {
            if index.isMultiple(of: 2) {
                evenTotal += 1
                if byte == 0 {
                    evenZeroCount += 1
                }
            } else {
                oddTotal += 1
                if byte == 0 {
                    oddZeroCount += 1
                }
            }
        }

        let evenZeroRatio = evenTotal == 0 ? 0 : Double(evenZeroCount) / Double(evenTotal)
        let oddZeroRatio = oddTotal == 0 ? 0 : Double(oddZeroCount) / Double(oddTotal)
        return max(evenZeroRatio, oddZeroRatio) > 0.55
            && min(evenZeroRatio, oddZeroRatio) < 0.20
    }
}

private extension Data {
    func hasDominantLeadingNULPrefix() -> Bool {
        guard let firstNonNULIndex = firstIndex(where: { $0 != 0 }) else {
            return true
        }
        let leadingNULCount = distance(from: startIndex, to: firstNonNULIndex)
        guard leadingNULCount >= 64 else {
            return false
        }
        return Double(leadingNULCount) / Double(count) > 0.5
    }
}
