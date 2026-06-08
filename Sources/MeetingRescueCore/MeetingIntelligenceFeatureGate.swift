public enum MeetingIntelligenceFeatureGate {
    public static func isVisibleLane(_ laneID: String) -> Bool {
        laneID != "context"
    }
}
