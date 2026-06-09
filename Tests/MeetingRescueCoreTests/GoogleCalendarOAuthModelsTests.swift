import Foundation
import Testing
@testable import MeetingRescueCore

struct GoogleCalendarOAuthModelsTests {
    @Test("OAuth client config는 secret 없이 앱 번들용 설정으로 decode된다")
    func decodesClientConfigWithoutSecret() throws {
        let json = """
        {
          "clientID": "606173227743-example.apps.googleusercontent.com",
          "redirectHost": "localhost",
          "scopes": ["https://www.googleapis.com/auth/calendar.events.readonly"]
        }
        """

        let config = try JSONDecoder().decode(GoogleCalendarOAuthClientConfig.self, from: Data(json.utf8))
        let oauth = config.oauthConfiguration(port: 49152)

        #expect(config.clientID == "606173227743-example.apps.googleusercontent.com")
        #expect(config.clientSecret == nil)
        #expect(config.redirectHost == "localhost")
        #expect(config.scopes == [GoogleCalendarOAuthConfiguration.calendarEventsReadonlyScope])
        #expect(oauth.clientSecret == nil)
        #expect(oauth.redirectURI == "http://localhost:49152/")
    }

    @Test("OAuth client config는 Desktop client secret을 optional runtime config로 보존한다")
    func decodesOptionalDesktopClientSecret() throws {
        let json = """
        {
          "clientID": "606173227743-example.apps.googleusercontent.com",
          "clientSecret": "desktop-secret",
          "redirectHost": "localhost"
        }
        """

        let config = try JSONDecoder().decode(GoogleCalendarOAuthClientConfig.self, from: Data(json.utf8))
        let oauth = config.oauthConfiguration(port: 49152)

        #expect(config.clientSecret == "desktop-secret")
        #expect(oauth.clientSecret == "desktop-secret")
        #expect(oauth.scopes == [GoogleCalendarOAuthConfiguration.calendarEventsReadonlyScope])
    }

    @Test("Google Console에서 받은 installed client JSON도 decode된다")
    func decodesDownloadedInstalledClientJSON() throws {
        let json = """
        {
          "installed": {
            "client_id": "606173227743-example.apps.googleusercontent.com",
            "client_secret": "desktop-secret",
            "redirect_uris": ["http://localhost"]
          }
        }
        """

        let config = try JSONDecoder().decode(GoogleCalendarOAuthClientConfig.self, from: Data(json.utf8))

        #expect(config.clientID == "606173227743-example.apps.googleusercontent.com")
        #expect(config.clientSecret == "desktop-secret")
        #expect(config.redirectHost == "localhost")
        #expect(config.scopes == [GoogleCalendarOAuthConfiguration.calendarEventsReadonlyScope])
    }

    @Test("PKCE challenge는 S256 base64url no-padding 값으로 생성된다")
    func makesS256PKCEChallenge() {
        let challenge = PKCEChallenge(verifier: "abc")

        #expect(challenge.verifier == "abc")
        #expect(challenge.challenge == "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0")
        #expect(challenge.method == "S256")
    }

    @Test("authorization URL에는 Calendar readonly scope와 PKCE 필드가 포함된다")
    func buildsAuthorizationURL() throws {
        let config = GoogleCalendarOAuthConfiguration(
            clientID: "client-id.apps.googleusercontent.com",
            redirectURI: "http://localhost:49152/",
            scopes: [GoogleCalendarOAuthConfiguration.calendarEventsReadonlyScope]
        )
        let pkce = PKCEChallenge(verifier: "abc")

        let url = try config.authorizationURL(pkce: pkce, state: "state-value")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(components.scheme == "https")
        #expect(components.host == "accounts.google.com")
        #expect(components.path == "/o/oauth2/v2/auth")
        #expect(queryItems["client_id"] == "client-id.apps.googleusercontent.com")
        #expect(queryItems["redirect_uri"] == "http://localhost:49152/")
        #expect(queryItems["response_type"] == "code")
        #expect(queryItems["access_type"] == "offline")
        #expect(queryItems["prompt"] == "consent")
        #expect(queryItems["scope"] == GoogleCalendarOAuthConfiguration.calendarEventsReadonlyScope)
        #expect(queryItems["code_challenge"] == pkce.challenge)
        #expect(queryItems["code_challenge_method"] == "S256")
        #expect(queryItems["state"] == "state-value")
    }

    @Test("token response는 access token, refresh token, expiry를 decode한다")
    func decodesTokenResponse() throws {
        let json = """
        {
          "access_token": "access-value",
          "refresh_token": "refresh-value",
          "expires_in": 3920,
          "scope": "https://www.googleapis.com/auth/calendar.events.readonly",
          "token_type": "Bearer"
        }
        """

        let response = try JSONDecoder().decode(GoogleCalendarTokenResponse.self, from: Data(json.utf8))

        #expect(response.accessToken == "access-value")
        #expect(response.refreshToken == "refresh-value")
        #expect(response.expiresIn == 3920)
        #expect(response.scope == GoogleCalendarOAuthConfiguration.calendarEventsReadonlyScope)
        #expect(response.tokenType == "Bearer")
    }
}
