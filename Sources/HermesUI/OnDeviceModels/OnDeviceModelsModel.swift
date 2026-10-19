#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The state behind Settings > On-device models (plan WP-65c, Q17, Q45): one row per downloadable model, the
    /// Apple model, the room the models use, and the question the screen asks before a big step. The rules for rows,
    /// buttons and deleting live in ``OnDeviceModelController``; this type keeps the screen current.
    @MainActor
    @Observable
    public final class OnDeviceModelsModel {
        /// A step the screen asks about first.
        public struct Question: Identifiable, Equatable, Sendable {
            public let action: OnDeviceModelRow.Action
            public let model: OnDeviceModel
            /// Bytes that arrived so far, for the "discard" question.
            public let receivedBytes: Int64

            public var id: String { "\(action)-\(model.id)" }
        }

        public private(set) var rows: [OnDeviceModelRow]
        public private(set) var appleModelIsInUse = true
        public private(set) var appleAvailability: LocalModelAvailability = .available
        /// True after a memory warning moved the answers back to the Apple model.
        public private(set) var isSuspendedByMemoryWarning = false
        /// False where nothing can run a downloaded model (the Simulator).
        public private(set) var canRunDownloadedModels = true
        /// Bytes the models use on this phone.
        public private(set) var usedBytes: Int64 = 0
        public private(set) var errorText: String?
        /// Set while the screen waits for a yes.
        public var question: Question?
        /// True while the model list shows as a sheet, opened from the "Get a better model" link in offline chat.
        public var isListPresented = false

        @ObservationIgnored private let controller: OnDeviceModelController
        @ObservationIgnored private let storage: OnDeviceModelStorage
        @ObservationIgnored private var states: [String: OnDeviceModelState] = [:]
        @ObservationIgnored private var lastDiskRead = ContinuousClock.now.advanced(by: .seconds(-10))
        @ObservationIgnored private var isFrozen = false

        public init(controller: OnDeviceModelController, storage: OnDeviceModelStorage) {
            self.controller = controller
            self.storage = storage
            rows = controller.rows(states: [:])
            refresh()
        }

        /// Keeps the rows current until the screen goes away. Call it from `.task`.
        public func run() async {
            guard !isFrozen else { return }
            await controller.manager.reload()
            let updates = await controller.manager.updates()
            refresh()
            for await update in updates {
                states[update.id] = update.state
                // Progress arrives many times a second. The disk is read at most once a second for it.
                let isProgress: Bool
                if case .downloading = update.state { isProgress = true } else { isProgress = false }
                refresh(readDisk: !isProgress || ContinuousClock.now - lastDiskRead > .seconds(1))
            }
        }

        /// Reads the choice, the memory notice and the disk again. The app calls it after a memory warning.
        public func refresh(readDisk: Bool = true) {
            rows = controller.rows(states: states)
            appleModelIsInUse = controller.appleModelIsInUse
            appleAvailability = controller.selection.apple.availability
            isSuspendedByMemoryWarning = controller.selection.isSuspendedByMemoryWarning
            canRunDownloadedModels = controller.selection.canRunDownloadedModels
            if readDisk {
                usedBytes = storage.usedBytes()
                lastDiskRead = .now
            }
        }

        // MARK: Buttons

        /// A row button was tapped. Big steps ask first.
        public func tap(_ action: OnDeviceModelRow.Action, on row: OnDeviceModelRow) {
            if row.needsConfirmation(action) {
                question = Question(action: action, model: row.model, receivedBytes: row.receivedBytes)
            } else {
                perform(action, on: row.model)
            }
        }

        /// The user said yes to the question on screen.
        public func confirm(_ question: Question) {
            self.question = nil
            perform(question.action, on: question.model)
        }

        /// Opens the model list as a sheet. Offline chat calls it from "Get a better model" (plan Q45).
        public func presentList() {
            isListPresented = true
        }

        /// Makes the Apple model the one that answers.
        public func useAppleModel() {
            Task {
                await controller.useAppleModel()
                refresh()
            }
        }

        private func perform(_ action: OnDeviceModelRow.Action, on model: OnDeviceModel) {
            errorText = nil
            Task {
                do {
                    try await controller.perform(action, on: model)
                } catch {
                    errorText = "Could not delete \(model.displayName): \(error.localizedDescription)"
                }
                refresh()
            }
        }

        // MARK: Previews

        /// Shows fixed states and stops listening to the manager. For previews.
        func freeze(states: [String: OnDeviceModelState], usedBytes: Int64) {
            isFrozen = true
            self.states = states
            refresh(readDisk: false)
            self.usedBytes = usedBytes
        }
    }

#endif
