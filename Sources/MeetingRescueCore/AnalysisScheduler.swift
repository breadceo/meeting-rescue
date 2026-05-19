import Foundation

public actor AnalysisScheduler {
    private var runningMeetingIDs: Set<String> = []
    private var activeMeetingID: String?
    private var latestSnapshots: [String: AnalysisSnapshot] = [:]

    public init() {}

    public func setActiveMeetingID(_ meetingID: String?) {
        activeMeetingID = meetingID
    }

    public func seedSnapshot(_ snapshot: AnalysisSnapshot?, for meetingID: String) {
        latestSnapshots[meetingID] = snapshot
    }

    public func runIfIdle(request: AnalysisRequest, provider: LLMProvider) async -> AnalysisRunResult {
        guard !runningMeetingIDs.contains(request.meetingID) else {
            return .skippedAlreadyRunning
        }

        runningMeetingIDs.insert(request.meetingID)
        defer {
            runningMeetingIDs.remove(request.meetingID)
        }

        do {
            let result = try await provider.analyze(request)
            guard activeMeetingID == nil || activeMeetingID == request.meetingID else {
                return .staleIgnored(previousSnapshot: latestSnapshots[request.meetingID])
            }
            let snapshot = result.snapshot
            latestSnapshots[request.meetingID] = snapshot
            return .success(snapshot, usage: result.usage, rawOutput: result.rawOutput, runTrace: result.runTrace)
        } catch {
            let providerError = error as? LLMProviderError
            return .failurePreserved(
                previousSnapshot: latestSnapshots[request.meetingID],
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                runTrace: providerError?.runTrace
            )
        }
    }
}
