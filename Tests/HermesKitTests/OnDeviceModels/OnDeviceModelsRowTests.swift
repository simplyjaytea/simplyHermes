import Foundation
import Testing

@testable import HermesKit

struct OnDeviceModelsRowTests {
    private let model = TestModels.alpha
    private let someProgress = OnDeviceModelProgress(receivedBytes: 10, totalBytes: 110)

    private func row(
        _ state: OnDeviceModelState, selected: Bool = false, canRun: Bool = true, memory: Int64? = nil
    ) -> OnDeviceModelRow {
        OnDeviceModelRow(model: model, state: state, isSelected: selected, canRun: canRun, availableMemoryBytes: memory)
    }

    @Test func eachStateOffersTheRightButtons() {
        #expect(row(.notDownloaded).actions == [.download])
        #expect(row(.queued).actions == [.cancel])
        #expect(row(.downloading(someProgress)).actions == [.pause, .cancel])
        #expect(row(.paused(someProgress)).actions == [.resume, .cancel])
        #expect(row(.failed(.network("lost"), someProgress)).actions == [.retry, .cancel])
        #expect(row(.failed(.server(status: 500), someProgress)).actions == [.retry, .cancel])
        #expect(row(.failed(.damaged(file: "config.json"), someProgress)).actions == [.retry, .cancel])
        #expect(row(.downloaded).actions == [.use, .delete])
    }

    @Test func noRoomHasNothingToCancel() {
        let failure = OnDeviceModelFailure.notEnoughSpace(needed: 2, available: 1)
        #expect(row(.failed(failure, someProgress)).actions == [.retry])
    }

    @Test func theModelInUseOffersOnlyDelete() {
        #expect(row(.downloaded, selected: true).actions == [.delete])
    }

    @Test func aModelThisDeviceCannotRunOffersOnlyDelete() {
        #expect(row(.downloaded, canRun: false).actions == [.delete])
    }

    @Test func onlyMovingOrWaitingRowsAreBusy() {
        #expect(row(.queued).isBusy)
        #expect(row(.downloading(someProgress)).isBusy)
        #expect(!row(.notDownloaded).isBusy)
        #expect(!row(.paused(someProgress)).isBusy)
        #expect(!row(.failed(.network("x"), someProgress)).isBusy)
        #expect(!row(.downloaded).isBusy)
    }

    @Test func theMemoryCautionAppearsOnlyWhenTheAllowanceIsBelowTheEstimate() {
        let estimate = model.estimatedMemoryBytes
        #expect(!row(.downloaded, memory: nil).mayNotFitInMemory)
        #expect(!row(.downloaded, memory: estimate).mayNotFitInMemory)
        #expect(!row(.downloaded, memory: estimate * 2).mayNotFitInMemory)
        #expect(row(.downloaded, memory: estimate - 1).mayNotFitInMemory)
    }

    @Test func bigStepsAskFirst() {
        let download = row(.notDownloaded)
        #expect(download.needsConfirmation(.download))
        #expect(row(.downloaded).needsConfirmation(.delete))
        #expect(row(.paused(someProgress)).needsConfirmation(.cancel))  // 10 bytes would be thrown away
        #expect(row(.failed(.network("x"), someProgress)).needsConfirmation(.cancel))
        #expect(row(.downloading(someProgress)).needsConfirmation(.cancel))
    }

    @Test func smallStepsDoNotAsk() {
        let nothingYet = OnDeviceModelProgress(receivedBytes: 0, totalBytes: 110)
        #expect(!row(.queued).needsConfirmation(.cancel))
        #expect(!row(.downloading(nothingYet)).needsConfirmation(.cancel))
        #expect(!row(.downloading(someProgress)).needsConfirmation(.pause))
        #expect(!row(.paused(someProgress)).needsConfirmation(.resume))
        #expect(!row(.failed(.network("x"), someProgress)).needsConfirmation(.retry))
        #expect(!row(.downloaded).needsConfirmation(.use))
    }

    @Test func receivedBytesComeFromTheProgressOfUnfinishedStates() {
        #expect(row(.notDownloaded).receivedBytes == 0)
        #expect(row(.queued).receivedBytes == 0)
        #expect(row(.downloaded).receivedBytes == 0)
        #expect(row(.downloading(someProgress)).receivedBytes == 10)
        #expect(row(.paused(someProgress)).receivedBytes == 10)
        #expect(row(.failed(.server(status: 500), someProgress)).receivedBytes == 10)
    }

    @Test func theRowTakesItsIDFromTheModel() {
        #expect(row(.notDownloaded).id == "alpha")
    }

    @Test func progressIsAFractionBetweenZeroAndOne() {
        #expect(OnDeviceModelProgress(receivedBytes: 25, totalBytes: 100).fraction == 0.25)
        #expect(OnDeviceModelProgress(receivedBytes: 0, totalBytes: 0).fraction == 0)
        #expect(OnDeviceModelProgress(receivedBytes: 200, totalBytes: 100).fraction == 1)
        #expect(OnDeviceModelProgress(receivedBytes: -5, totalBytes: 100).fraction == 0)
    }
}
