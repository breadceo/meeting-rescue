public enum MomentMarkerRunMode: Sendable {
    case liveWatch
    case history
    case testRun
}

public enum MomentMarkerAvailability {
    public static func isVisible(runMode: MomentMarkerRunMode) -> Bool {
        switch runMode {
        case .liveWatch, .testRun:
            return true
        case .history:
            return false
        }
    }

    public static func canAdd(
        runMode: MomentMarkerRunMode,
        hasActiveTranscript: Bool,
        hasTranscriptPreview: Bool
    ) -> Bool {
        isVisible(runMode: runMode) && hasActiveTranscript && hasTranscriptPreview
    }
}
