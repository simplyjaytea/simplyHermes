import Foundation
import Testing

@testable import HermesKit

/// Row 120: the memory fit before download.
struct OnDeviceModelFitTests {
    private let model = OnDeviceModelCatalog.standard.models[2]
    private var need: Int64 { model.estimatedMemoryBytes }

    /// A phone whose ceiling is exactly `bytes`.
    private func phone(ceiling bytes: Int64) -> UInt64 {
        UInt64((Double(bytes) / OnDeviceModelFit.appShare).rounded(.up))
    }

    @Test func unknownNumbersNeverBlock() {
        #expect(OnDeviceModelFit.assess(model, physicalMemory: 0, available: nil) == .fits)
        #expect(OnDeviceModelFit.ceiling(physicalMemory: 0) == nil)
    }

    @Test func theTableFromTheSpec() {
        let roomy = phone(ceiling: need * 2)
        #expect(OnDeviceModelFit.assess(model, physicalMemory: roomy, available: need) == .fits, "exactly enough now")
        #expect(OnDeviceModelFit.assess(model, physicalMemory: roomy, available: nil) == .fits, "now unknown")
        #expect(
            OnDeviceModelFit.assess(model, physicalMemory: roomy, available: need - 1)
                == .mayNotFit(availableBytes: need - 1))
        let small = phone(ceiling: need / 2)
        guard case .tooBig = OnDeviceModelFit.assess(model, physicalMemory: small, available: need * 4) else {
            Issue.record("a phone whose ceiling is half the need can never run it")
            return
        }
    }

    @Test func theCeilingBoundaryIsExact() throws {
        let ceiling = try #require(OnDeviceModelFit.ceiling(physicalMemory: phone(ceiling: need)))
        #expect(ceiling >= need)
        let atCeiling = UInt64(Double(need) / OnDeviceModelFit.appShare)
        let justUnder = OnDeviceModelFit.ceiling(physicalMemory: atCeiling - 4096) ?? 0
        #expect(justUnder < need)
        if case .tooBig = OnDeviceModelFit.assess(model, physicalMemory: atCeiling - 4096, available: nil) {
        } else {
            Issue.record("just under the ceiling is too big")
        }
    }

    @Test func aTooBigModelOffersNoDownloadButADownloadedOneKeepsDelete() {
        let small = phone(ceiling: need / 2)
        let fresh = OnDeviceModelRow(model: model, state: .notDownloaded, deviceMemoryBytes: small)
        #expect(fresh.actions.isEmpty)
        let kept = OnDeviceModelRow(model: model, state: .downloaded, deviceMemoryBytes: small)
        #expect(kept.actions.contains(.delete), "never deleted for the user, and they can remove it")
    }

    @Test func mayNotFitKeepsDownloadAndTheConfirmation() {
        let row = OnDeviceModelRow(
            model: model, state: .notDownloaded, availableMemoryBytes: need - 1,
            deviceMemoryBytes: phone(ceiling: need * 2))
        #expect(row.actions == [.download])
        #expect(row.needsConfirmation(.download))
        #expect(row.mayNotFitInMemory)
    }

    @Test func theControllerPassesTheDeviceMemory() async throws {
        let fixture = try ControllerFitFixture()
        let rows = fixture.controller(deviceMemory: phone(ceiling: 1)).rows(states: [:])
        #expect(rows.allSatisfy { $0.actions.isEmpty }, "a tiny phone is offered nothing")
        let roomy = fixture.controller(deviceMemory: 64 * 1_073_741_824).rows(states: [:])
        #expect(roomy.allSatisfy { $0.actions == [.download] })
    }
}

/// The same pieces the controller tests use, for the device-memory pass-through.
private struct ControllerFitFixture {
    let manager: OnDeviceModelManager
    let selection: OnDeviceModelSelection

    init() throws {
        let env = TestEnvironment()
        let downloader = MockModelDownloader(
            models: TestModels.catalog.models, directory: env.root.appendingPathComponent("downloads"))
        manager = OnDeviceModelManager(
            catalog: TestModels.catalog, storage: env.storage, downloader: downloader,
            diskSpace: FixedDiskSpace(bytes: 1_000_000), reserveBytes: 100, progressStep: 1)
        selection = OnDeviceModelSelection(
            apple: StubExecutor(name: "apple"), storage: env.storage, catalog: TestModels.catalog, runtime: nil)
    }

    func controller(deviceMemory: UInt64) -> OnDeviceModelController {
        OnDeviceModelController(
            manager: manager, selection: selection, catalog: TestModels.catalog, deviceMemory: deviceMemory)
    }
}
