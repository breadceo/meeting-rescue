import Foundation

enum AppVersion {
    static var shortVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static var displayTitle: String {
        if let shortVersion, !shortVersion.isEmpty {
            return "Meeting Rescue v\(shortVersion)"
        }
        return "Meeting Rescue"
    }
}
