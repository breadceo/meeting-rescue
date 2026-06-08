import Foundation

public enum UpdateFeedConfiguration {
    public static func isSparkleConfigured(infoDictionary: [String: Any]) -> Bool {
        guard let feedURLString = trimmedString(infoDictionary["SUFeedURL"]),
              let feedURL = URL(string: feedURLString),
              ["http", "https"].contains(feedURL.scheme?.lowercased()),
              trimmedString(infoDictionary["SUPublicEDKey"]) != nil else {
            return false
        }

        return true
    }

    private static func trimmedString(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
