import Foundation

public enum GoogleCalendarTokenAvailability: String, Codable, Equatable, Sendable {
    case missingRefreshToken
    case validAccessToken
    case refreshRequired
    case revoked
}

public struct GoogleCalendarTokenState: Codable, Equatable, Sendable {
    public var accessToken: String?
    public var refreshToken: String?
    public var accessTokenExpiresAt: Date?
    public var isRevoked: Bool

    public init(
        accessToken: String? = nil,
        refreshToken: String? = nil,
        accessTokenExpiresAt: Date? = nil,
        isRevoked: Bool = false
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.isRevoked = isRevoked
    }

    public init(response: GoogleCalendarTokenResponse, receivedAt: Date) {
        self.init(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            accessTokenExpiresAt: receivedAt.addingTimeInterval(TimeInterval(response.expiresIn)),
            isRevoked: false
        )
    }

    public func updated(
        with response: GoogleCalendarTokenResponse,
        receivedAt: Date
    ) -> GoogleCalendarTokenState {
        GoogleCalendarTokenState(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            accessTokenExpiresAt: receivedAt.addingTimeInterval(TimeInterval(response.expiresIn)),
            isRevoked: false
        )
    }

    public func availability(
        now: Date,
        expirySkewSeconds: TimeInterval = 60
    ) -> GoogleCalendarTokenAvailability {
        if isRevoked {
            return .revoked
        }
        guard refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return .missingRefreshToken
        }
        guard let accessToken, !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let accessTokenExpiresAt else {
            return .refreshRequired
        }
        if accessTokenExpiresAt <= now.addingTimeInterval(expirySkewSeconds) {
            return .refreshRequired
        }
        return .validAccessToken
    }
}
