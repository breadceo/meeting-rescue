import Foundation
import Sparkle

@MainActor
final class SparkleUpdater: NSObject, ObservableObject {
    @Published private(set) var blockingSheetDismissalRequestID = UUID()

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: self
    )

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        requestBlockingSheetDismissal()
        controller.checkForUpdates(nil)
    }

    private func requestBlockingSheetDismissal() {
        blockingSheetDismissalRequestID = UUID()
    }
}

extension SparkleUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        requestBlockingSheetDismissal()
    }

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        requestBlockingSheetDismissal()
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        requestBlockingSheetDismissal()
    }
}

extension SparkleUpdater: @preconcurrency SPUStandardUserDriverDelegate {
    func standardUserDriverWillShowModalAlert() {
        requestBlockingSheetDismissal()
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        requestBlockingSheetDismissal()
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        requestBlockingSheetDismissal()
    }
}
