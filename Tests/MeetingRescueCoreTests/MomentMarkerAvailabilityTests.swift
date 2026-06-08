import Testing
@testable import MeetingRescueCore

@Suite("Moment marker availability")
struct MomentMarkerAvailabilityTests {
    @Test("live watch와 test run에서만 중요 시점을 표시할 수 있다")
    func allowsMomentMarkersOnlyForLiveAndTestRun() {
        #expect(MomentMarkerAvailability.isVisible(runMode: .liveWatch))
        #expect(MomentMarkerAvailability.isVisible(runMode: .testRun))
        #expect(!MomentMarkerAvailability.isVisible(runMode: .history))
    }

    @Test("중요 시점 표시는 활성 transcript와 preview line이 필요하다")
    func requiresActiveTranscriptAndPreviewLines() {
        #expect(MomentMarkerAvailability.canAdd(
            runMode: .liveWatch,
            hasActiveTranscript: true,
            hasTranscriptPreview: true
        ))
        #expect(MomentMarkerAvailability.canAdd(
            runMode: .testRun,
            hasActiveTranscript: true,
            hasTranscriptPreview: true
        ))
        #expect(!MomentMarkerAvailability.canAdd(
            runMode: .history,
            hasActiveTranscript: true,
            hasTranscriptPreview: true
        ))
        #expect(!MomentMarkerAvailability.canAdd(
            runMode: .liveWatch,
            hasActiveTranscript: false,
            hasTranscriptPreview: true
        ))
        #expect(!MomentMarkerAvailability.canAdd(
            runMode: .liveWatch,
            hasActiveTranscript: true,
            hasTranscriptPreview: false
        ))
    }
}
