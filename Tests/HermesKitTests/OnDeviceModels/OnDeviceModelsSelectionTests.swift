import Foundation
import Testing

@testable import HermesKit

struct OnDeviceModelsSelectionTests {
    private let alpha = TestModels.alpha
    private let beta = TestModels.beta

    /// A selection over a temp folder with the given models on disk, a stub Apple model and a stub runtime.
    private struct Setup {
        let env: TestEnvironment
        let apple: StubExecutor
        let runtime: StubRuntime
        let models: [String: StubExecutor]
        let enabled: TestFlag
        let selection: OnDeviceModelSelection
        private let hasRuntime: Bool

        init(
            installed: [OnDeviceModel] = [TestModels.alpha], runnable: Set<String> = ["alpha", "beta"],
            hasRuntime: Bool = true
        ) throws {
            let env = TestEnvironment()
            let models = Dictionary(
                uniqueKeysWithValues: runnable.map { ($0, StubExecutor(name: $0)) })
            self.env = env
            self.models = models
            self.hasRuntime = hasRuntime
            apple = StubExecutor(name: "apple")
            runtime = StubRuntime(executors: models)
            enabled = TestFlag(true)
            for model in installed { try env.installFinished(model) }
            selection = Setup.makeSelection(
                env: env, apple: apple, runtime: hasRuntime ? runtime : nil, enabled: enabled)
        }

        /// Another selection over the same folder, as after a relaunch.
        func relaunched() -> OnDeviceModelSelection {
            Setup.makeSelection(env: env, apple: apple, runtime: hasRuntime ? runtime : nil, enabled: enabled)
        }

        private static func makeSelection(
            env: TestEnvironment, apple: StubExecutor, runtime: StubRuntime?, enabled: TestFlag
        ) -> OnDeviceModelSelection {
            OnDeviceModelSelection(
                apple: apple, storage: env.storage, catalog: TestModels.catalog, runtime: runtime,
                isEnabled: { enabled.value })
        }
    }

    private func answer(_ selection: OnDeviceModelSelection, _ prompt: String) async throws -> String {
        try await selection.respond(instructions: "Be brief.", prompt: prompt)
    }

    // MARK: Routing

    @Test func startsOnTheAppleModel() async throws {
        let setup = try Setup()
        #expect(setup.selection.choice == .apple)
        #expect(setup.selection.route == .apple)
        #expect(try await answer(setup.selection, "hi") == "apple: hi")
        #expect(setup.runtime.requestedModels.isEmpty)
    }

    @Test func aDownloadedChoiceAnswersWithTheRuntimeModel() async throws {
        let setup = try Setup()
        await setup.selection.select(.downloaded("alpha"))
        #expect(setup.selection.route == .downloaded(alpha))
        #expect(try await answer(setup.selection, "hi") == "alpha: hi")
        #expect(try await answer(setup.selection, "again") == "alpha: again")
        #expect(setup.runtime.requestedModels == ["alpha"])  // made once, then reused
        #expect(setup.apple.prompts.isEmpty)
    }

    @Test func theChoiceIsSavedForTheNextLaunch() async throws {
        let setup = try Setup()
        await setup.selection.select(.downloaded("alpha"))
        #expect(setup.env.storage.loadChoice() == .downloaded("alpha"))
        let relaunched = setup.relaunched()
        #expect(relaunched.choice == .downloaded("alpha"))
        #expect(relaunched.route == .downloaded(alpha))
    }

    @Test func aHandleTakenEarlyFollowsTheChoice() async throws {
        let setup = try Setup()
        let handle: any LocalModelExecutor = setup.selection
        #expect(try await handle.respond(instructions: "", prompt: "1") == "apple: 1")
        await setup.selection.select(.downloaded("alpha"))
        #expect(try await handle.respond(instructions: "", prompt: "2") == "alpha: 2")
        await setup.selection.select(.apple)
        #expect(try await handle.respond(instructions: "", prompt: "3") == "apple: 3")
    }

    @Test func theAppleModelStaysReachableForHelpers() async throws {
        let setup = try Setup()
        await setup.selection.select(.downloaded("alpha"))
        #expect(try await setup.selection.apple.respond(instructions: "", prompt: "title") == "apple: title")
    }

    // MARK: Fallbacks

    @Test func aModelThatIsNotOnThePhoneFallsBackToApple() async throws {
        let setup = try Setup(installed: [])
        await setup.selection.select(.downloaded("alpha"))
        #expect(setup.selection.choice == .downloaded("alpha"))
        #expect(setup.selection.route == .apple)
        #expect(try await answer(setup.selection, "hi") == "apple: hi")
    }

    @Test func aModelOutsideTheCatalogFallsBackToApple() async throws {
        let setup = try Setup()
        await setup.selection.select(.downloaded("retired"))
        #expect(setup.selection.route == .apple)
        #expect(try await answer(setup.selection, "hi") == "apple: hi")
    }

    @Test func withoutARuntimeTheAppleModelAlwaysAnswers() async throws {
        let setup = try Setup(hasRuntime: false)
        await setup.selection.select(.downloaded("alpha"))
        #expect(!setup.selection.canRunDownloadedModels)
        #expect(setup.selection.route == .apple)
        #expect(try await answer(setup.selection, "hi") == "apple: hi")
    }

    @Test func aRuntimeThatCannotRunTheModelFallsBackToApple() async throws {
        let setup = try Setup(installed: [alpha, beta], runnable: ["beta"])
        #expect(setup.selection.canRunDownloadedModels)
        await setup.selection.select(.downloaded("alpha"))
        #expect(setup.selection.route == .apple)
        await setup.selection.select(.downloaded("beta"))
        #expect(setup.selection.route == .downloaded(beta))
    }

    @Test func deletedFilesMakeTheRouteFallBack() async throws {
        let setup = try Setup()
        await setup.selection.select(.downloaded("alpha"))
        #expect(setup.selection.route == .downloaded(alpha))
        try setup.env.storage.remove(alpha)
        #expect(setup.selection.route == .apple)
        #expect(try await answer(setup.selection, "hi") == "apple: hi")
    }

    // MARK: Availability and the Settings switch

    @Test func theSettingsSwitchTurnsEveryAnswerOff() async throws {
        let setup = try Setup()
        #expect(setup.selection.availability == .available)
        setup.enabled.value = false
        #expect(setup.selection.availability == .unavailable(.switchedOff))
        await setup.selection.select(.downloaded("alpha"))
        #expect(setup.selection.availability == .unavailable(.switchedOff))
        setup.enabled.value = true
        #expect(setup.selection.availability == .available)
    }

    @Test func availabilityComesFromTheModelThatAnswers() async throws {
        let setup = try Setup()
        setup.apple.availability = .unavailable(.disabled)
        #expect(setup.selection.availability == .unavailable(.disabled))
        // A downloaded model does not need Apple Intelligence.
        await setup.selection.select(.downloaded("alpha"))
        #expect(setup.selection.availability == .available)
        setup.models["alpha"]?.availability = .unavailable(.unsupported)
        #expect(setup.selection.availability == .unavailable(.unsupported))
    }

    // MARK: Memory

    @Test func aMemoryWarningUnloadsAndLetsTheAppleModelAnswer() async throws {
        let setup = try Setup()
        await setup.selection.select(.downloaded("alpha"))
        #expect(try await answer(setup.selection, "one") == "alpha: one")
        let unloadsBefore = setup.runtime.unloadCount

        await setup.selection.handleMemoryWarning()

        #expect(setup.runtime.unloadCount == unloadsBefore + 1)
        #expect(setup.selection.isSuspendedByMemoryWarning)
        #expect(setup.selection.choice == .downloaded("alpha"))  // the user's pick is kept
        #expect(setup.selection.route == .apple)
        #expect(try await answer(setup.selection, "two") == "apple: two")
    }

    @Test func pickingTheModelAgainAfterAWarningLoadsItAgain() async throws {
        let setup = try Setup()
        await setup.selection.select(.downloaded("alpha"))
        await setup.selection.handleMemoryWarning()
        #expect(setup.selection.route == .apple)

        await setup.selection.select(.downloaded("alpha"))

        #expect(!setup.selection.isSuspendedByMemoryWarning)
        #expect(setup.selection.route == .downloaded(alpha))
        #expect(try await answer(setup.selection, "back") == "alpha: back")
    }

    @Test func aMemoryWarningWithTheAppleModelChosenStillUnloads() async throws {
        let setup = try Setup()
        await setup.selection.handleMemoryWarning()
        #expect(setup.runtime.unloadCount == 1)
        #expect(!setup.selection.isSuspendedByMemoryWarning)
        #expect(setup.selection.route == .apple)
    }

    @Test func aMemoryWarningWithoutARuntimeIsHarmless() async throws {
        let setup = try Setup(hasRuntime: false)
        await setup.selection.handleMemoryWarning()
        #expect(setup.selection.route == .apple)
        #expect(try await answer(setup.selection, "hi") == "apple: hi")
    }

    @Test func notEnoughMemoryWhileLoadingFallsBackForThatCall() async throws {
        let setup = try Setup()
        await setup.selection.select(.downloaded("alpha"))
        setup.models["alpha"]?.failure = OnDeviceModelError.notEnoughMemory(needed: 10, available: 5)
        let unloadsBefore = setup.runtime.unloadCount

        #expect(try await answer(setup.selection, "hi") == "apple: hi")

        #expect(setup.models["alpha"]?.prompts == ["hi"])  // the downloaded model was tried first
        #expect(setup.selection.isSuspendedByMemoryWarning)
        #expect(setup.runtime.unloadCount == unloadsBefore + 1)
        #expect(try await answer(setup.selection, "next") == "apple: next")  // and stays out of the way
        #expect(setup.models["alpha"]?.prompts == ["hi"])
    }

    @Test func otherErrorsFromTheDownloadedModelReachTheCaller() async throws {
        let setup = try Setup()
        await setup.selection.select(.downloaded("alpha"))
        setup.models["alpha"]?.failure = TestFailure()
        await #expect(throws: TestFailure()) {
            try await self.answer(setup.selection, "hi")
        }
        #expect(!setup.selection.isSuspendedByMemoryWarning)
        #expect(setup.apple.prompts.isEmpty)
    }

    @Test func theMemoryGateLetsAModelLoadWhenTheFigureIsUnknownOrEnough() throws {
        let estimate = alpha.estimatedMemoryBytes
        try OnDeviceMemoryGate { nil }.check(alpha)
        try OnDeviceMemoryGate { estimate }.check(alpha)
        try OnDeviceMemoryGate { estimate * 2 }.check(alpha)
    }

    @Test func theMemoryGateRefusesAModelThatDoesNotFit() {
        let estimate = alpha.estimatedMemoryBytes
        let gate = OnDeviceMemoryGate { estimate - 1 }
        #expect(throws: OnDeviceModelError.notEnoughMemory(needed: estimate, available: estimate - 1)) {
            try gate.check(alpha)
        }
    }

    @Test func theMemoryGateChecksTheLoadButNotTheAnswersAfterIt() async throws {
        let estimate = alpha.estimatedMemoryBytes
        let free = FreeMemory(estimate)
        let gate = OnDeviceMemoryGate { free.bytes }

        let first = try await gate.answer(with: alpha) { "one" }  // there is room to load
        // The weights count against the app now, so the free figure is lower by their size.
        free.bytes = estimate - alpha.weightBytes
        let second = try await gate.answer(with: alpha) { "two" }  // loaded: not refused for its own weights
        let third = try await gate.answer(with: alpha) { "three" }

        #expect([first, second, third] == ["one", "two", "three"])
    }

    @Test func theMemoryGateChecksAgainAfterAnUnload() async throws {
        let estimate = alpha.estimatedMemoryBytes
        let free = FreeMemory(estimate)
        let gate = OnDeviceMemoryGate { free.bytes }
        _ = try await gate.answer(with: alpha) { "one" }
        free.bytes = estimate - alpha.weightBytes

        gate.noteUnloaded()

        let refusal = OnDeviceModelError.notEnoughMemory(needed: estimate, available: estimate - alpha.weightBytes)
        await #expect(throws: refusal) {
            try await gate.answer(with: alpha) { "two" }
        }
    }

    @Test func anAnswerThatRanAcrossAnUnloadIsNotRememberedAsLoaded() async throws {
        let estimate = alpha.estimatedMemoryBytes
        let free = FreeMemory(estimate)
        let gate = OnDeviceMemoryGate { free.bytes }
        // A memory warning unloads the models while the first answer is still running.
        let unloadedMidAnswer: () async throws -> String = {
            gate.noteUnloaded()
            return "one"
        }
        let first = try await gate.answer(with: alpha, unloadedMidAnswer)
        free.bytes = estimate - alpha.weightBytes

        #expect(first == "one")
        let refusal = OnDeviceModelError.notEnoughMemory(needed: estimate, available: estimate - alpha.weightBytes)
        await #expect(throws: refusal) {
            try await gate.answer(with: alpha) { "two" }
        }
    }

    @Test func aFailedAnswerIsNotRememberedAsLoaded() async {
        let estimate = alpha.estimatedMemoryBytes
        let free = FreeMemory(estimate)
        let gate = OnDeviceMemoryGate { free.bytes }
        let broken: () async throws -> String = { throw TestFailure() }
        await #expect(throws: TestFailure()) {
            try await gate.answer(with: alpha, broken)
        }
        free.bytes = estimate - 1

        let refusal = OnDeviceModelError.notEnoughMemory(needed: estimate, available: estimate - 1)
        await #expect(throws: refusal) {
            try await gate.answer(with: alpha) { "next" }
        }
    }

    @Test func aModelThatDoesNotFitIsRefusedBeforeItRuns() async {
        let estimate = alpha.estimatedMemoryBytes
        let gate = OnDeviceMemoryGate { estimate - 1 }
        let ran = TestFlag(false)

        let work: () async throws -> String = {
            ran.value = true
            return "never"
        }

        let refusal = OnDeviceModelError.notEnoughMemory(needed: estimate, available: estimate - 1)
        await #expect(throws: refusal) {
            try await gate.answer(with: alpha, work)
        }

        #expect(!ran.value)
    }

    // MARK: Changing and deleting

    @Test func switchingModelsUnloadsTheOldOne() async throws {
        let setup = try Setup(installed: [alpha, beta])
        await setup.selection.select(.downloaded("alpha"))
        #expect(setup.runtime.unloadCount == 1)
        await setup.selection.select(.downloaded("alpha"))  // same pick: nothing to unload
        #expect(setup.runtime.unloadCount == 1)
        await setup.selection.select(.downloaded("beta"))
        #expect(setup.runtime.unloadCount == 2)
        await setup.selection.select(.apple)
        #expect(setup.runtime.unloadCount == 3)
    }

    @Test func deletingTheModelInUseFallsBackToAppleAndForgetsIt() async throws {
        let setup = try Setup()
        await setup.selection.select(.downloaded("alpha"))
        #expect(try await answer(setup.selection, "hi") == "alpha: hi")
        let unloadsBefore = setup.runtime.unloadCount

        await setup.selection.modelWillBeDeleted("alpha")

        #expect(setup.selection.choice == .apple)
        #expect(setup.env.storage.loadChoice() == .apple)
        #expect(setup.runtime.unloadCount == unloadsBefore + 1)
        // Downloaded and picked again, the model gets a fresh executor, not the one that held the old files.
        await setup.selection.select(.downloaded("alpha"))
        #expect(setup.selection.route == .downloaded(alpha))
        #expect(setup.runtime.requestedModels == ["alpha", "alpha"])
    }

    @Test func deletingAnotherModelKeepsTheChoice() async throws {
        let setup = try Setup(installed: [alpha, beta])
        await setup.selection.select(.downloaded("alpha"))
        await setup.selection.modelWillBeDeleted("beta")
        #expect(setup.selection.choice == .downloaded("alpha"))
        #expect(setup.selection.route == .downloaded(alpha))
    }

    /// The free-memory figure of a test, which the test can lower while the gate reads it.
    private final class FreeMemory: @unchecked Sendable {
        private let lock = NSLock()
        private var current: Int64

        init(_ bytes: Int64) {
            current = bytes
        }

        var bytes: Int64 {
            get { lock.withLock { current } }
            set { lock.withLock { current = newValue } }
        }
    }
}
