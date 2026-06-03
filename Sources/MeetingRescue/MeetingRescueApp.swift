import SwiftUI

@main
struct MeetingRescueApp: App {
    @StateObject private var viewModel = AppViewModel()
    @StateObject private var sparkleUpdater = SparkleUpdater()

    var body: some Scene {
        WindowGroup(AppVersion.displayTitle) {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(sparkleUpdater)
        }
        .commands {
            CommandMenu("Meeting") {
                Button("Bookmark Current Moment") {
                    viewModel.addLiveBookmark()
                }
                .keyboardShortcut("b", modifiers: [.command])
                .disabled(!viewModel.canAddLiveBookmark)
            }

            CommandGroup(after: .appInfo) {
                Button("업데이트 확인...") {
                    sparkleUpdater.checkForUpdates()
                }
                .disabled(!sparkleUpdater.canCheckForUpdates)
            }
        }
    }
}
