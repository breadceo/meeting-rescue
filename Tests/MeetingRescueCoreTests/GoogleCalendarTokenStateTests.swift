import Foundation
import Testing
@testable import MeetingRescueCore

struct GoogleCalendarTokenStateTests {
    @Test("token response는 expiry timestamp와 refresh token을 가진 저장 상태로 변환된다")
    func tokenResponseCreatesStoredState() {
        let response = GoogleCalendarTokenResponse(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            expiresIn: 3600,
            scope: GoogleCalendarOAuthConfiguration.calendarEventsReadonlyScope,
            tokenType: "Bearer"
        )
        let receivedAt = Date(timeIntervalSince1970: 1_000)

        let state = GoogleCalendarTokenState(response: response, receivedAt: receivedAt)

        #expect(state.accessToken == "access-1")
        #expect(state.refreshToken == "refresh-1")
        #expect(state.accessTokenExpiresAt == Date(timeIntervalSince1970: 4_600))
        #expect(state.availability(now: Date(timeIntervalSince1970: 1_100)) == .validAccessToken)
    }

    @Test("refresh response에 refresh token이 없으면 기존 refresh token을 유지한다")
    func refreshResponseKeepsExistingRefreshToken() {
        let existing = GoogleCalendarTokenState(
            accessToken: "old-access",
            refreshToken: "refresh-1",
            accessTokenExpiresAt: Date(timeIntervalSince1970: 2_000)
        )
        let response = GoogleCalendarTokenResponse(
            accessToken: "new-access",
            refreshToken: nil,
            expiresIn: 3600,
            scope: nil,
            tokenType: "Bearer"
        )

        let updated = existing.updated(with: response, receivedAt: Date(timeIntervalSince1970: 3_000))

        #expect(updated.accessToken == "new-access")
        #expect(updated.refreshToken == "refresh-1")
        #expect(updated.accessTokenExpiresAt == Date(timeIntervalSince1970: 6_600))
    }

    @Test("token availability는 missing, refresh required, revoked를 분리한다")
    func tokenAvailabilityStates() {
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(GoogleCalendarTokenState().availability(now: now) == .missingRefreshToken)
        #expect(
            GoogleCalendarTokenState(
                accessToken: "access",
                refreshToken: "refresh",
                accessTokenExpiresAt: Date(timeIntervalSince1970: 1_030)
            ).availability(now: now, expirySkewSeconds: 60) == .refreshRequired
        )
        #expect(
            GoogleCalendarTokenState(
                accessToken: "access",
                refreshToken: "refresh",
                accessTokenExpiresAt: Date(timeIntervalSince1970: 2_000),
                isRevoked: true
            ).availability(now: now) == .revoked
        )
    }
}
