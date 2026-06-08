import Testing
@testable import MeetingRescueCore

struct MeetingIntelligenceFeatureGateTests {
    @Test("release visible intelligence lanes include context tab")
    func releaseVisibleLanesIncludeContextTab() {
        #expect(MeetingIntelligenceFeatureGate.isVisibleLane("overview"))
        #expect(MeetingIntelligenceFeatureGate.isVisibleLane("timeline"))
        #expect(MeetingIntelligenceFeatureGate.isVisibleLane("candidates"))
        #expect(MeetingIntelligenceFeatureGate.isVisibleLane("workflow"))
        #expect(MeetingIntelligenceFeatureGate.isVisibleLane("context"))
    }
}
