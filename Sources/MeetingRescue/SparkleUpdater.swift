import Foundation
import MeetingRescueCore
import Sparkle

@MainActor
final class SparkleUpdater: NSObject, ObservableObject {
    struct AvailableUpdate: Equatable {
        let version: String
    }

    @Published private(set) var blockingSheetDismissalRequestID = UUID()
    @Published private(set) var availableUpdate: AvailableUpdate?

    private let isSparkleConfigured: Bool

    override init() {
        self.isSparkleConfigured = UpdateFeedConfiguration.isSparkleConfigured(
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        )
        super.init()
    }

    private lazy var controller: SPUStandardUpdaterController? = {
        guard isSparkleConfigured else {
            return nil
        }

        return SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }()

    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    func checkForUpdates() {
        guard let controller else {
            return
        }

        requestBlockingSheetDismissal()
        controller.checkForUpdates(nil)
    }

    func showAvailableUpdate() {
        guard let controller else {
            return
        }

        requestBlockingSheetDismissal()
        controller.checkForUpdates(nil)
    }

    private func requestBlockingSheetDismissal() {
        blockingSheetDismissalRequestID = UUID()
    }

    private func registerAvailableUpdate(_ item: SUAppcastItem) {
        availableUpdate = AvailableUpdate(version: item.displayVersionString)
    }

    private func clearAvailableUpdate() {
        availableUpdate = nil
    }
}

extension SparkleUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        registerAvailableUpdate(item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        clearAvailableUpdate()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        clearAvailableUpdate()
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if choice == .install || choice == .skip {
            clearAvailableUpdate()
        }
    }

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
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverWillShowModalAlert() {
        requestBlockingSheetDismissal()
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        registerAvailableUpdate(update)
        return false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        registerAvailableUpdate(update)
        if state.userInitiated || handleShowingUpdate {
            requestBlockingSheetDismissal()
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        requestBlockingSheetDismissal()
    }
}
