import AppKit
import Foundation
import MeetingRescueCore
import Network
import Security

enum GoogleCalendarConnectionState: Equatable {
    case notConfigured
    case disconnected
    case connected
    case needsLogin
    case failed(String)

    var displayText: String {
        switch self {
        case .notConfigured:
            return "Google Calendar OAuth config가 없습니다."
        case .disconnected:
            return "Google Calendar 연결 전"
        case .connected:
            return "Google Calendar 연결됨"
        case .needsLogin:
            return "Google Calendar 다시 로그인 필요"
        case .failed(let message):
            return message
        }
    }
}

enum GoogleCalendarIntegrationError: LocalizedError {
    case missingConfig
    case missingClientSecret
    case missingRefreshToken
    case invalidAuthorizationState
    case userDenied
    case adminPolicy(String)
    case tokenRevoked
    case network(String)
    case invalidResponse
    case needsRefreshRetry
    case oauth(String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            return "Google Calendar OAuth config가 없습니다."
        case .missingClientSecret:
            return "현재 Desktop OAuth client는 client secret이 필요합니다."
        case .missingRefreshToken:
            return "Google Calendar 다시 로그인이 필요합니다."
        case .invalidAuthorizationState:
            return "Google Calendar 인증 state가 일치하지 않습니다."
        case .userDenied:
            return "Google Calendar 접근 권한이 필요합니다."
        case .adminPolicy(let message):
            return message.isEmpty ? "관리자 승인 또는 앱 접근 권한이 필요합니다." : message
        case .tokenRevoked:
            return "Google Calendar 다시 로그인 필요"
        case .network(let message):
            return "Google Calendar 네트워크 실패: \(message)"
        case .invalidResponse:
            return "Google Calendar 응답을 해석할 수 없습니다."
        case .needsRefreshRetry:
            return "Google Calendar access token 갱신이 필요합니다."
        case .oauth(let message):
            return message
        }
    }
}

enum GoogleCalendarOAuthConfigLoader {
    static let environmentPathKey = "MEETING_RESCUE_GOOGLE_CALENDAR_OAUTH_CONFIG"
    private static let resourceBundleName = "MeetingRescue_MeetingRescue.bundle"
    private static let configResourceName = "GoogleCalendarOAuthConfig"
    private static let configFileName = "\(configResourceName).json"

    static func load(
        bundle: Bundle? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runtimeResourceRoots: [URL] = Self.defaultRuntimeResourceRoots()
    ) throws -> GoogleCalendarOAuthClientConfig {
        if let path = environment[environmentPathKey],
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try load(url: URL(fileURLWithPath: path))
        }

        for url in candidateConfigURLs(bundle: bundle, runtimeResourceRoots: runtimeResourceRoots) {
            if FileManager.default.fileExists(atPath: url.path) {
                return try load(url: url)
            }
        }

        throw GoogleCalendarIntegrationError.missingConfig
    }

    private static func candidateConfigURLs(bundle: Bundle?, runtimeResourceRoots: [URL]) -> [URL] {
        var candidates = [URL]()
        if let url = bundle?.url(forResource: configResourceName, withExtension: "json") {
            candidates.append(url)
        }
        if let url = Bundle.main.url(forResource: configResourceName, withExtension: "json") {
            candidates.append(url)
        }
        for root in runtimeResourceRoots {
            candidates.append(
                root
                    .appendingPathComponent(resourceBundleName, isDirectory: true)
                    .appendingPathComponent(configFileName)
            )
            candidates.append(
                root
                    .appendingPathComponent(resourceBundleName, isDirectory: true)
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent(configFileName)
            )
            candidates.append(root.appendingPathComponent(configFileName))
        }
        return candidates.reduce(into: [URL]()) { uniqueCandidates, url in
            if !uniqueCandidates.contains(url) {
                uniqueCandidates.append(url)
            }
        }
    }

    private static func defaultRuntimeResourceRoots() -> [URL] {
        [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent()
        ].compactMap { $0 }
    }

    private static func load(url: URL) throws -> GoogleCalendarOAuthClientConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GoogleCalendarOAuthClientConfig.self, from: data)
    }
}

protocol GoogleCalendarRefreshTokenStore {
    func loadRefreshToken() throws -> String?
    func saveRefreshToken(_ refreshToken: String) throws
    func deleteRefreshToken() throws
}

final class GoogleCalendarKeychainTokenStore: GoogleCalendarRefreshTokenStore {
    private let service: String
    private let account: String

    init(service: String = "MeetingRescue.GoogleCalendar", account: String) {
        self.service = service
        self.account = account
    }

    func loadRefreshToken() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw GoogleCalendarIntegrationError.network("Keychain load failed: \(status)")
        }
        guard let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func saveRefreshToken(_ refreshToken: String) throws {
        let data = Data(refreshToken.utf8)
        var query = baseQuery()
        let update: [String: Any] = [
            kSecValueData as String: data
        ]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw GoogleCalendarIntegrationError.network("Keychain update failed: \(status)")
        }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw GoogleCalendarIntegrationError.network("Keychain save failed: \(addStatus)")
        }
    }

    func deleteRefreshToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GoogleCalendarIntegrationError.network("Keychain delete failed: \(status)")
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

final class GoogleCalendarService: @unchecked Sendable {
    private let config: GoogleCalendarOAuthClientConfig
    private let tokenStore: GoogleCalendarRefreshTokenStore
    private let session: URLSession
    private var tokenState = GoogleCalendarTokenState()

    init(
        config: GoogleCalendarOAuthClientConfig,
        tokenStore: GoogleCalendarRefreshTokenStore,
        session: URLSession = .shared
    ) {
        self.config = config
        self.tokenStore = tokenStore
        self.session = session
    }

    func hasStoredRefreshToken() -> Bool {
        ((try? tokenStore.loadRefreshToken()) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func connect(timeoutSeconds: TimeInterval = 180) async throws {
        let server = try GoogleCalendarOAuthLoopbackServer()
        let port = try server.start()
        let oauth = config.oauthConfiguration(port: port)
        let verifier = PKCEChallenge.randomVerifier()
        let pkce = PKCEChallenge(verifier: verifier)
        let state = Self.randomURLSafeString(byteCount: 24)
        let url = try oauth.authorizationURL(pkce: pkce, state: state)

        NSWorkspace.shared.open(url)

        let redirect = try await server.waitForRedirect(timeoutSeconds: timeoutSeconds)
        guard redirect.state == state else {
            throw GoogleCalendarIntegrationError.invalidAuthorizationState
        }
        if let error = redirect.error {
            throw Self.mapOAuthError(error, description: nil)
        }
        guard let code = redirect.code else {
            throw GoogleCalendarIntegrationError.invalidResponse
        }

        let response = try await exchangeAuthorizationCode(
            oauth: oauth,
            code: code,
            verifier: verifier
        )
        tokenState = GoogleCalendarTokenState(response: response, receivedAt: Date())
        if let refreshToken = tokenState.refreshToken {
            try tokenStore.saveRefreshToken(refreshToken)
        } else if let existingRefreshToken = try tokenStore.loadRefreshToken() {
            tokenState.refreshToken = existingRefreshToken
        } else {
            throw GoogleCalendarIntegrationError.missingRefreshToken
        }
    }

    func disconnect() throws {
        tokenState = GoogleCalendarTokenState()
        try tokenStore.deleteRefreshToken()
    }

    func fetchEvents(request: GoogleCalendarEventsListRequest) async throws -> GoogleCalendarEventsListResponse {
        let accessToken = try await ensureAccessToken()
        do {
            return try await fetchEvents(accessToken: accessToken, request: request)
        } catch GoogleCalendarIntegrationError.needsRefreshRetry {
            let refreshed = try await refreshAccessToken()
            return try await fetchEvents(accessToken: refreshed, request: request)
        }
    }

    private func ensureAccessToken() async throws -> String {
        switch tokenState.availability(now: Date()) {
        case .validAccessToken:
            guard let accessToken = tokenState.accessToken else {
                throw GoogleCalendarIntegrationError.missingRefreshToken
            }
            return accessToken
        case .missingRefreshToken:
            guard let refreshToken = try tokenStore.loadRefreshToken() else {
                throw GoogleCalendarIntegrationError.missingRefreshToken
            }
            tokenState.refreshToken = refreshToken
            return try await refreshAccessToken()
        case .refreshRequired:
            return try await refreshAccessToken()
        case .revoked:
            throw GoogleCalendarIntegrationError.tokenRevoked
        }
    }

    private func refreshAccessToken() async throws -> String {
        let storedRefreshToken = try tokenStore.loadRefreshToken()
        guard let refreshToken = tokenState.refreshToken ?? storedRefreshToken else {
            throw GoogleCalendarIntegrationError.missingRefreshToken
        }
        let oauth = config.oauthConfiguration(port: 0)
        let response = try await postTokenForm([
            "client_id": oauth.clientID,
            "client_secret": oauth.clientSecret ?? "",
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])
        tokenState = tokenState.updated(with: response, receivedAt: Date())
        tokenState.refreshToken = refreshToken
        return response.accessToken
    }

    private func exchangeAuthorizationCode(
        oauth: GoogleCalendarOAuthConfiguration,
        code: String,
        verifier: String
    ) async throws -> GoogleCalendarTokenResponse {
        try await postTokenForm([
            "client_id": oauth.clientID,
            "client_secret": oauth.clientSecret ?? "",
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": oauth.redirectURI
        ])
    }

    private func postTokenForm(_ values: [String: String]) async throws -> GoogleCalendarTokenResponse {
        if values["client_secret"]?.isEmpty == true {
            throw GoogleCalendarIntegrationError.missingClientSecret
        }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = GoogleCalendarFormURLEncoder.encode(values)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GoogleCalendarIntegrationError.network(error.localizedDescription)
        }
        try validateTokenHTTPResponse(response, data: data, requestValues: values)
        return try JSONDecoder().decode(GoogleCalendarTokenResponse.self, from: data)
    }

    private func fetchEvents(
        accessToken: String,
        request: GoogleCalendarEventsListRequest
    ) async throws -> GoogleCalendarEventsListResponse {
        var urlRequest = URLRequest(url: try request.url())
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw GoogleCalendarIntegrationError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw GoogleCalendarIntegrationError.needsRefreshRetry
        }
        try validateCalendarHTTPResponse(response, data: data)
        return try JSONDecoder().decode(GoogleCalendarEventsListResponse.self, from: data)
    }

    private func validateTokenHTTPResponse(_ response: URLResponse, data: Data, requestValues: [String: String]) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarIntegrationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.withTokenRequestDebug(
                Self.mapGoogleError(data: data, statusCode: http.statusCode),
                requestValues: requestValues
            )
        }
    }

    private func validateCalendarHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarIntegrationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapGoogleError(data: data, statusCode: http.statusCode)
        }
    }

    private static func mapGoogleError(data: Data, statusCode: Int) -> GoogleCalendarIntegrationError {
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let nestedError = payload?["error"] as? [String: Any]
        let error = (payload?["error"] as? String) ?? (nestedError?["status"] as? String)
        let description = (payload?["error_description"] as? String) ?? (nestedError?["message"] as? String)
        if error == "admin_policy_enforced" || description?.contains("admin_policy_enforced") == true || statusCode == 403 {
            return .adminPolicy(description ?? "관리자 승인 또는 앱 접근 권한이 필요합니다.")
        }
        if error == "access_denied" {
            return .userDenied
        }
        if error == "invalid_grant" {
            return .tokenRevoked
        }
        if description?.contains("client_secret is missing") == true {
            return .missingClientSecret
        }
        let rawSnippet = String(data: data, encoding: .utf8)?
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(300)
        let messageParts = [error, description]
            .compactMap { value -> String? in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
        let joinedMessage = messageParts.joined(separator: ": ")
        let message = joinedMessage.isEmpty ? nil : joinedMessage
        if let message, let rawSnippet, message == "INVALID_ARGUMENT: Bad Request" || message == "Bad Request" {
            return .oauth("\(message) \(rawSnippet)")
        }
        return .oauth(message ?? rawSnippet.map { "Google Calendar 요청 실패: HTTP \(statusCode): \($0)" } ?? "Google Calendar 요청 실패: HTTP \(statusCode)")
    }

    private static func withTokenRequestDebug(
        _ error: GoogleCalendarIntegrationError,
        requestValues: [String: String]
    ) -> GoogleCalendarIntegrationError {
        guard case .oauth(let message) = error else {
            return error
        }
        let codeLength = requestValues["code"]?.count ?? 0
        let verifierLength = requestValues["code_verifier"]?.count ?? 0
        let hasClientSecret = requestValues["client_secret"]?.isEmpty == false
        let redirectURI = requestValues["redirect_uri"] ?? ""
        let grantType = requestValues["grant_type"] ?? ""
        return .oauth(
            "\(message) [request grant_type=\(grantType) redirect_uri=\(redirectURI) code_length=\(codeLength) code_verifier_length=\(verifierLength) client_secret_present=\(hasClientSecret)]"
        )
    }

    private static func mapOAuthError(_ error: String, description: String?) -> GoogleCalendarIntegrationError {
        if error == "access_denied" {
            return .userDenied
        }
        if error == "admin_policy_enforced" {
            return .adminPolicy(description ?? "관리자 승인 또는 앱 접근 권한이 필요합니다.")
        }
        return .oauth(description ?? error)
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

}

enum GoogleCalendarFormURLEncoder {
    private static let allowedCharacters: CharacterSet = {
        var characters = CharacterSet.alphanumerics
        characters.insert(charactersIn: "-._~")
        return characters
    }()

    static func encode(_ values: [String: String]) -> Data {
        values
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private static func percentEncode(_ value: String) -> String {
        (value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value)
            .replacingOccurrences(of: "%20", with: "+")
    }
}

struct GoogleCalendarOAuthRedirect {
    var code: String?
    var error: String?
    var state: String?
}

private final class GoogleCalendarOAuthLoopbackStartState: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Int, Error>?

    func finish(_ result: Result<Int, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard self.result == nil else {
            return
        }
        self.result = result
    }

    func port() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        switch result {
        case .success(let port):
            return port
        case .failure(let error):
            throw error
        case nil:
            throw GoogleCalendarIntegrationError.invalidResponse
        }
    }
}

final class GoogleCalendarOAuthLoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "meeting-rescue.google-calendar-oauth-loopback")
    private var continuation: CheckedContinuation<GoogleCalendarOAuthRedirect, Error>?
    private var didFinish = false
    private var pendingResult: Result<GoogleCalendarOAuthRedirect, Error>?

    init() throws {
        self.listener = try NWListener(using: .tcp, on: .any)
    }

    func start() throws -> Int {
        let ready = DispatchSemaphore(value: 0)
        let startState = GoogleCalendarOAuthLoopbackStartState()

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                guard let port = self?.listener.port?.rawValue, port > 0 else {
                    startState.finish(.failure(GoogleCalendarIntegrationError.invalidResponse))
                    ready.signal()
                    return
                }
                startState.finish(.success(Int(port)))
                ready.signal()
            case .failed(let error):
                startState.finish(.failure(GoogleCalendarIntegrationError.network(error.localizedDescription)))
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)

        if ready.wait(timeout: .now() + 5) == .timedOut {
            listener.cancel()
            throw GoogleCalendarIntegrationError.network("OAuth loopback listener did not start")
        }
        return try startState.port()
    }

    fileprivate func waitForRedirect(timeoutSeconds: TimeInterval) async throws -> GoogleCalendarOAuthRedirect {
        try await withThrowingTaskGroup(of: GoogleCalendarOAuthRedirect.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.queue.async {
                        if let pendingResult = self.pendingResult {
                            self.pendingResult = nil
                            switch pendingResult {
                            case .success(let redirect):
                                continuation.resume(returning: redirect)
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        } else {
                            self.continuation = continuation
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw GoogleCalendarIntegrationError.network("OAuth redirect timeout")
            }
            let result = try await group.next()!
            group.cancelAll()
            cancel()
            return result
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(on: connection, buffer: Data())
    }

    private func receiveHTTPRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, _ in
            guard let self else {
                return
            }
            var requestData = buffer
            if let data {
                requestData.append(data)
            }

            if GoogleCalendarOAuthHTTPRedirectParser.hasCompleteHTTPRequest(data: requestData) {
                let redirect = GoogleCalendarOAuthHTTPRedirectParser.parse(data: requestData)
                self.sendCallbackResponse(on: connection)
                if let redirect {
                    self.finish(.success(redirect))
                }
                return
            }

            if requestData.count > 32_768 {
                self.sendCallbackResponse(on: connection)
                self.finish(.failure(GoogleCalendarIntegrationError.invalidResponse))
                return
            }

            self.receiveHTTPRequest(on: connection, buffer: requestData)
        }
    }

    private func sendCallbackResponse(on connection: NWConnection) {
        let body = """
        <html><body><h1>Meeting Rescue authorization received.</h1><p>You can close this browser tab.</p></body></html>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(Data(body.utf8).count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ result: Result<GoogleCalendarOAuthRedirect, Error>) {
        queue.async {
            guard !self.didFinish else {
                return
            }
            self.didFinish = true
            self.listener.cancel()
            if let continuation = self.continuation {
                switch result {
                case .success(let redirect):
                    continuation.resume(returning: redirect)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            } else {
                self.pendingResult = result
            }
            self.continuation = nil
        }
    }

    private func cancel() {
        queue.async {
            self.listener.cancel()
        }
    }

}

enum GoogleCalendarOAuthHTTPRedirectParser {
    static func hasCompleteHTTPRequest(data: Data) -> Bool {
        data.range(of: Data("\r\n\r\n".utf8)) != nil || data.range(of: Data("\n\n".utf8)) != nil
    }

    static func parse(data: Data) -> GoogleCalendarOAuthRedirect? {
        guard hasCompleteHTTPRequest(data: data) else {
            return nil
        }
        guard let request = String(data: data, encoding: .utf8),
              let requestLine = request.components(separatedBy: "\r\n").first else {
            return nil
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return nil
        }
        let path = String(parts[1])
        guard let components = URLComponents(string: "http://localhost\(path)") else {
            return nil
        }
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        return GoogleCalendarOAuthRedirect(
            code: values["code"],
            error: values["error"],
            state: values["state"]
        )
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

private extension PKCEChallenge {
    static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}
