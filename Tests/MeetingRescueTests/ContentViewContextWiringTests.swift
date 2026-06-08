import Foundation
import Testing

struct ContentViewContextWiringTests {
    @Test("context intelligence lane renders the context panel")
    func contextLaneRendersContextPanel() throws {
        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/MeetingRescue/ContentView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("case .context:\n                            contextPanel()"))
        #expect(!source.contains("case .context:\n                            EmptyView()"))
    }
}
