import Testing
@testable import MeetingRescueCore

struct MeetingIntelligenceFeatureGateTests {
    @Test("release visible intelligence lanes hide context tab")
    func releaseVisibleLanesHideContextTab() {
        #expect(MeetingIntelligenceFeatureGate.isVisibleLane("overview"))
        #expect(MeetingIntelligenceFeatureGate.isVisibleLane("timeline"))
        #expect(MeetingIntelligenceFeatureGate.isVisibleLane("candidates"))
        #expect(MeetingIntelligenceFeatureGate.isVisibleLane("workflow"))
        #expect(!MeetingIntelligenceFeatureGate.isVisibleLane("context"))
    }
}
