import Foundation

public enum TranscriptFileAppendPlan: Equatable, Sendable {
    case unchanged
    case appended
    case reload
}

public struct TranscriptFileReadAnchor: Equatable, Sendable {
    public let byteCount: UInt64
    public let prefixSample: Data
    public let suffixSample: Data
    public let sampleByteLimit: Int

    public init(data: Data = Data(), sampleByteLimit: Int = 16_384) {
        let safeLimit = max(1, sampleByteLimit)
        self.byteCount = UInt64(data.count)
        self.prefixSample = data.prefixSample(byteLimit: safeLimit)
        self.suffixSample = data.suffixSample(endingAt: UInt64(data.count), byteLimit: safeLimit)
        self.sampleByteLimit = safeLimit
    }

    private init(byteCount: UInt64, prefixSample: Data, suffixSample: Data, sampleByteLimit: Int) {
        self.byteCount = byteCount
        self.prefixSample = prefixSample
        self.suffixSample = suffixSample
        self.sampleByteLimit = sampleByteLimit
    }

    public func advanced(withAppendedData appendedData: Data) -> TranscriptFileReadAnchor {
        var nextPrefix = prefixSample
        let remainingPrefixBytes = max(0, sampleByteLimit - nextPrefix.count)
        if remainingPrefixBytes > 0 {
            nextPrefix.append(appendedData.prefixSample(byteLimit: remainingPrefixBytes))
        }

        var suffixSource = suffixSample
        suffixSource.append(appendedData)
        let nextSuffix = suffixSource.suffixSample(
            endingAt: UInt64(suffixSource.count),
            byteLimit: sampleByteLimit
        )

        return TranscriptFileReadAnchor(
            byteCount: byteCount + UInt64(appendedData.count),
            prefixSample: nextPrefix,
            suffixSample: nextSuffix,
            sampleByteLimit: sampleByteLimit
        )
    }
}

public enum TranscriptFileAppendPlanner {
    public static func plan(
        fileSize: UInt64,
        previousAnchor: TranscriptFileReadAnchor,
        currentPrefixSample: Data,
        currentSuffixSampleAtPreviousEnd: Data
    ) -> TranscriptFileAppendPlan {
        guard fileSize >= previousAnchor.byteCount else {
            return .reload
        }
        guard currentPrefixSample == previousAnchor.prefixSample,
              currentSuffixSampleAtPreviousEnd == previousAnchor.suffixSample else {
            return .reload
        }
        return fileSize == previousAnchor.byteCount ? .unchanged : .appended
    }
}

public extension Data {
    func prefixSample(byteLimit: Int) -> Data {
        Data(prefix(Swift.max(0, byteLimit)))
    }

    func suffixSample(endingAt endOffset: UInt64, byteLimit: Int) -> Data {
        let safeEndOffset = Swift.min(endOffset, UInt64(count))
        let end = Int(safeEndOffset)
        let start = Swift.max(0, end - Swift.max(0, byteLimit))
        return subdata(in: start..<end)
    }
}
