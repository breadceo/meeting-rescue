import Foundation
import Testing
@testable import MeetingRescue

struct GoogleCalendarOAuthLoopbackServerTests {
    @Test func startWaitsUntilEphemeralPortIsAssigned() throws {
        for _ in 0..<10 {
            let server = try GoogleCalendarOAuthLoopbackServer()

            let port = try server.start()

            #expect(port > 0)
        }
    }

    @Test func tokenFormEncodingEscapesReservedOAuthValues() {
        let body = String(
            data: GoogleCalendarFormURLEncoder.encode([
                "code": "4/0A+b=c",
                "redirect_uri": "http://localhost:49152/"
            ]),
            encoding: .utf8
        )

        #expect(body?.contains("code=4%2F0A%2Bb%3Dc") == true)
        #expect(body?.contains("redirect_uri=http%3A%2F%2Flocalhost%3A49152%2F") == true)
    }

    @Test func redirectParserWaitsForCompleteHTTPRequestBeforeReadingCode() {
        let partialRequest = Data("GET /?code=4%2Fpartial&state=s HTTP/1.1\r\nHost: localhost".utf8)
        let completeRequest = Data("GET /?code=4%2Fcomplete&state=s HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)

        #expect(GoogleCalendarOAuthHTTPRedirectParser.parse(data: partialRequest) == nil)

        let redirect = GoogleCalendarOAuthHTTPRedirectParser.parse(data: completeRequest)
        #expect(redirect?.code == "4/complete")
        #expect(redirect?.state == "s")
    }
}
