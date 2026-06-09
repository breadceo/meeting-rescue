import CryptoKit
import Foundation

public struct GoogleCalendarOAuthClientConfig: Codable, Equatable, Sendable {
    public var clientID: String
    public var clientSecret: String?
    public var redirectHost: String
    public var scopes: [String]

    public init(
        clientID: String,
        clientSecret: String? = nil,
        redirectHost: String = "localhost",
        scopes: [String] = [GoogleCalendarOAuthConfiguration.calendarEventsReadonlyScope]
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.redirectHost = redirectHost
        self.scopes = scopes
    }

    public func oauthConfiguration(port: Int) -> GoogleCalendarOAuthConfiguration {
        GoogleCalendarOAuthConfiguration(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: "http://\(formattedRedirectHost):\(port)/",
            scopes: scopes
        )
    }

    private enum CodingKeys: String, CodingKey {
        case clientID
        case clientSecret
        case redirectHost
        case scopes
        case installed
    }

    private enum InstalledCodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
        case redirectURIs = "redirect_uris"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.installed) {
            let installed = try container.nestedContainer(keyedBy: InstalledCodingKeys.self, forKey: .installed)
            let redirectURI = (try? installed.decode([String].self, forKey: .redirectURIs).first) ?? "http://localhost"
            let redirectHost = URL(string: redirectURI)?.host ?? "localhost"
            self.init(
                clientID: try installed.decode(String.self, forKey: .clientID),
                clientSecret: try installed.decodeIfPresent(String.self, forKey: .clientSecret),
                redirectHost: redirectHost,
                scopes: [GoogleCalendarOAuthConfiguration.calendarEventsReadonlyScope]
            )
            return
        }

        self.init(
            clientID: try container.decode(String.self, forKey: .clientID),
            clientSecret: try container.decodeIfPresent(String.self, forKey: .clientSecret),
            redirectHost: (try? container.decode(String.self, forKey: .redirectHost)) ?? "localhost",
            scopes: (try? container.decode([String].self, forKey: .scopes)) ?? [GoogleCalendarOAuthConfiguration.calendarEventsReadonlyScope]
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientID, forKey: .clientID)
        try container.encodeIfPresent(clientSecret, forKey: .clientSecret)
        try container.encode(redirectHost, forKey: .redirectHost)
        try container.encode(scopes, forKey: .scopes)
    }

    private var formattedRedirectHost: String {
        if redirectHost.contains(":"), !redirectHost.hasPrefix("[") {
            return "[\(redirectHost)]"
        }
        return redirectHost
    }
}

public struct GoogleCalendarOAuthConfiguration: Equatable, Sendable {
    public static let calendarEventsReadonlyScope = "https://www.googleapis.com/auth/calendar.events.readonly"

    public var clientID: String
    public var clientSecret: String?
    public var redirectURI: String
    public var scopes: [String]

    public init(
        clientID: String,
        clientSecret: String? = nil,
        redirectURI: String,
        scopes: [String] = [GoogleCalendarOAuthConfiguration.calendarEventsReadonlyScope]
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.redirectURI = redirectURI
        self.scopes = scopes
    }

    public func authorizationURL(pkce: PKCEChallenge, state: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "accounts.google.com"
        components.path = "/o/oauth2/v2/auth"
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components.url else {
            throw GoogleCalendarOAuthError.invalidAuthorizationURL
        }
        return url
    }
}

public struct PKCEChallenge: Equatable, Sendable {
    public var verifier: String
    public var challenge: String
    public var method: String

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Self.s256Challenge(for: verifier)
        self.method = "S256"
    }

    public init(verifier: String, challenge: String, method: String = "S256") {
        self.verifier = verifier
        self.challenge = challenge
        self.method = method
    }

    public static func s256Challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

public struct GoogleCalendarTokenResponse: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresIn: Int
    public var scope: String?
    public var tokenType: String

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresIn: Int,
        scope: String? = nil,
        tokenType: String
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.scope = scope
        self.tokenType = tokenType
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }
}

public enum GoogleCalendarOAuthError: Error, Equatable, Sendable {
    case invalidAuthorizationURL
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
