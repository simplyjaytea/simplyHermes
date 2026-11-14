import Foundation
import Testing

@testable import HermesKit

/// A model that loads, or fails to, and counts its loads.
private final class LoadingExecutor: LocalModelExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var failure: (any Error)?
    private var loads = 0

    func failLoad(with error: any Error) { lock.withLock { failure = error } }
    var loadCount: Int { lock.withLock { loads } }

    var availability: LocalModelAvailability { .available }
    func respond(instructions: String, prompt: String) async throws -> String { "answer" }
    func load() async throws {
        let error = lock.withLock { () -> (any Error)? in
            loads += 1
            return failure
        }
        if let error { throw error }
    }
}

private final class LoadingRuntime: OnDeviceModelRuntime, @unchecked Sendable {
    let executor: LoadingExecutor
    init(_ executor: LoadingExecutor) { self.executor = executor }
    func executor(for model: OnDeviceModel, folder: URL) -> (any LocalModelExecutor)? { executor }
    func unloadAll() async {}
}

/// A runtime that cannot run any model: the Simulator, or iOS 26 and older.
private final class NoRunRuntime: OnDeviceModelRuntime, @unchecked Sendable {
    func executor(for model: OnDeviceModel, folder: URL) -> (any LocalModelExecutor)? { nil }
    func unloadAll() async {}
}

/// The test environments, kept so their folders outlive the selection a test builds from them.
private let environments = EnvironmentKeeper()

private final class EnvironmentKeeper: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [TestEnvironment] = []
    func keep(_ environment: TestEnvironment) { lock.withLock { kept.append(environment) } }
}

/// WP-9, AT-5: the pill always says which model will answer and why another cannot.
struct OnDeviceModelsStatusTests {
    private let alpha = TestModels.alpha
    private var gemma: ModelIdentity { .downloaded(id: alpha.id, displayName: alpha.displayName) }

    private func selection(
        runtime: (any OnDeviceModelRuntime)?, installed: Bool = true, enabled: TestFlag = TestFlag(true),
        apple: StubExecutor = StubExecutor(name: "apple")
    ) throws -> (OnDeviceModelSelection, TestEnvironment) {
        let env = TestEnvironment()
        environments.keep(env)
        if installed { try env.installFinished(alpha) }
        let selection = OnDeviceModelSelection(
            apple: apple, storage: env.storage, catalog: TestModels.catalog, runtime: runtime,
            isEnabled: { enabled.value })
        return (selection, env)
    }

    @Test func theAppleModelIsReadyWhenItCanAnswer() throws {
        let (selection, _) = try selection(runtime: nil)
        #expect(selection.status == .ready(answeredBy: .apple))
    }

    @Test func switchedOffReadsOffAndAnUnavailableAppleModelReadsNoModel() throws {
        let off = TestFlag(false)
        #expect(try selection(runtime: nil, enabled: off).0.status == .off)
        let apple = StubExecutor(name: "apple")
        apple.availability = .unavailable(.disabled)
        #expect(try selection(runtime: nil, apple: apple).0.status == .noModel)
    }

    @Test func aChosenModelIsNotLoadedUntilPrepared() async throws {
        let executor = LoadingExecutor()
        let (selection, _) = try selection(runtime: LoadingRuntime(executor))
        await selection.select(.downloaded("alpha"))
        #expect(selection.status == .notLoaded(alpha))

        let status = await selection.prepare()
        #expect(status == .ready(answeredBy: gemma))
        #expect(selection.status == .ready(answeredBy: gemma))
        #expect(executor.loadCount == 1)
    }

    // AT-5: with no runtime the status says why. It does not quietly read as the Apple model.
    @Test func aChosenModelThatCannotRunSaysWhyInsteadOfReadingAsApple() async throws {
        let (noRuntime, _) = try selection(runtime: nil)
        await noRuntime.select(.downloaded("alpha"))
        #expect(noRuntime.status == .failed(gemma, reason: .runtimeUnavailable))

        let (cannotRun, _) = try selection(runtime: NoRunRuntime())
        await cannotRun.select(.downloaded("alpha"))
        #expect(cannotRun.status == .failed(gemma, reason: .runtimeUnavailable))
        #expect(cannotRun.cannotAnswerReason == .runtimeUnavailable)
        // Preparing it does not load anything and does not turn into the Apple model.
        #expect(await cannotRun.prepare() == .failed(gemma, reason: .runtimeUnavailable))
    }

    @Test func aMemoryRefusalIsAStatusWithBothNumbersAndNoSilentSwitch() async throws {
        let executor = LoadingExecutor()
        executor.failLoad(with: OnDeviceModelError.notEnoughMemory(needed: 3_000, available: 1_000))
        let (selection, _) = try selection(runtime: LoadingRuntime(executor))
        await selection.select(.downloaded("alpha"))
        let status = await selection.prepare()
        #expect(status == .failed(gemma, reason: .notEnoughMemory(needed: 3_000, available: 1_000)))
        #expect(selection.choice == .downloaded("alpha"))
    }

    @Test func aLoadErrorIsAStatusWithItsReason() async throws {
        let executor = LoadingExecutor()
        executor.failLoad(with: TestFailure(message: "corrupt weights"))
        let (selection, _) = try selection(runtime: LoadingRuntime(executor))
        await selection.select(.downloaded("alpha"))
        guard case .failed(let identity, .loadError(let text)) = await selection.prepare() else {
            Issue.record("expected a load failure")
            return
        }
        #expect(identity == gemma)
        #expect(text.contains("corrupt weights"))
    }

    @Test func aMemoryWarningAfterTheLoadMakesTheStatusSayWhy() async throws {
        let executor = LoadingExecutor()
        let (selection, _) = try selection(runtime: LoadingRuntime(executor))
        await selection.select(.downloaded("alpha"))
        await selection.prepare()
        await selection.handleMemoryWarning()
        guard case .failed(let identity, .notEnoughMemory) = selection.status else {
            Issue.record("expected a memory failure, got \(selection.status)")
            return
        }
        #expect(identity == gemma)
        // Picking the model again lets it load again.
        await selection.select(.downloaded("alpha"))
        #expect(selection.status == .notLoaded(alpha))
    }

    @Test func aModelWhoseFilesAreMissingReadsAsFailedNotAsApple() async throws {
        let executor = LoadingExecutor()
        let (selection, _) = try selection(runtime: LoadingRuntime(executor), installed: false)
        await selection.select(.downloaded("alpha"))
        #expect(selection.status == .failed(gemma, reason: .loadError("The model's files are not on this iPhone.")))
    }

    @Test func aDeletedModelReadsNoModel() async throws {
        let executor = LoadingExecutor()
        let (selection, _) = try selection(runtime: LoadingRuntime(executor))
        await selection.select(.downloaded("alpha"))
        await selection.prepare()
        await selection.modelWillBeDeleted("alpha")
        #expect(selection.status == .noModel)
    }

    @Test func theAppleModelNeedsNoLoad() async throws {
        let (selection, _) = try selection(runtime: nil)
        #expect(await selection.prepare() == .ready(answeredBy: .apple))
    }
}
