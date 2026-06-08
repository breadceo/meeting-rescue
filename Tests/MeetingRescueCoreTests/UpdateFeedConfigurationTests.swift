import Testing
@testable import MeetingRescueCore

@Suite("Update feed configuration")
struct UpdateFeedConfigurationTests {
    @Test("Sparkle update checks require both feed URL and public key")
    func requiresFeedURLAndPublicKey() {
        #expect(!UpdateFeedConfiguration.isSparkleConfigured(infoDictionary: [:]))
        #expect(!UpdateFeedConfiguration.isSparkleConfigured(infoDictionary: [
            "SUFeedURL": "https://raw.githubusercontent.com/breadceo/meeting-rescue-updates/main/appcast.xml"
        ]))
        #expect(!UpdateFeedConfiguration.isSparkleConfigured(infoDictionary: [
            "SUPublicEDKey": "public-key"
        ]))
        #expect(UpdateFeedConfiguration.isSparkleConfigured(infoDictionary: [
            "SUFeedURL": "https://raw.githubusercontent.com/breadceo/meeting-rescue-updates/main/appcast.xml",
            "SUPublicEDKey": "public-key"
        ]))
    }

    @Test("Sparkle update checks reject empty or malformed feed URLs")
    func rejectsInvalidFeedURL() {
        #expect(!UpdateFeedConfiguration.isSparkleConfigured(infoDictionary: [
            "SUFeedURL": "",
            "SUPublicEDKey": "public-key"
        ]))
        #expect(!UpdateFeedConfiguration.isSparkleConfigured(infoDictionary: [
            "SUFeedURL": "not-a-url",
            "SUPublicEDKey": "public-key"
        ]))
        #expect(!UpdateFeedConfiguration.isSparkleConfigured(infoDictionary: [
            "SUFeedURL": "ftp://example.com/appcast.xml",
            "SUPublicEDKey": "public-key"
        ]))
    }
}
