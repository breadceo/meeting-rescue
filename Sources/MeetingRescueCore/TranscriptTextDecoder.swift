import Foundation

public enum TranscriptTextDecoder {
    public static func decode(_ data: Data) -> String {
        guard !data.isEmpty else {
            return ""
        }

        if data.starts(with: [0xFF, 0xFE]) {
            return String(data: data, encoding: .utf16LittleEndian) ?? String(decoding: data, as: UTF8.self)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16BigEndian) ?? String(decoding: data, as: UTF8.self)
        }

        if likelyUTF16(data) {
            return String(data: data, encoding: .utf16LittleEndian)
                ?? String(data: data, encoding: .utf16BigEndian)
                ?? String(decoding: data, as: UTF8.self)
        }

        return String(decoding: data, as: UTF8.self)
    }

    private static func likelyUTF16(_ data: Data) -> Bool {
        let sample = data.prefix(200)
        guard sample.count >= 8 else {
            return false
        }
        let zeroCount = sample.filter { $0 == 0 }.count
        return Double(zeroCount) / Double(sample.count) > 0.20
    }
}
