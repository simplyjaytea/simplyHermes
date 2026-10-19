import Foundation

/// What Settings shows for one model in the catalog, and what the user can do with it. The wording lives in the UI;
/// this type decides which buttons exist so the rules can be tested without a screen.
public struct OnDeviceModelRow: Sendable, Equatable, Identifiable {
    public enum Action: Sendable, Hashable {
        /// Ask to download (the screen confirms the size first).
        case download
        case pause
        case resume
        /// Try a failed download again.
        case retry
        /// Stop and throw away the part that arrived.
        case cancel
        /// Remove the model from the phone.
        case delete
        /// Make this the model that answers.
        case use
    }

    public let model: OnDeviceModel
    public let state: OnDeviceModelState
    /// True when this is the model that answers now.
    public let isSelected: Bool
    /// True when a downloaded model could run on this device.
    public let canRun: Bool
    /// What this app may still allocate right now, if the device says.
    public let availableMemoryBytes: Int64?

    public init(
        model: OnDeviceModel, state: OnDeviceModelState, isSelected: Bool = false, canRun: Bool = true,
        availableMemoryBytes: Int64? = nil
    ) {
        self.model = model
        self.state = state
        self.isSelected = isSelected
        self.canRun = canRun
        self.availableMemoryBytes = availableMemoryBytes
    }

    public var id: String { model.id }

    /// The buttons for this row, main one first.
    public var actions: [Action] {
        switch state {
        case .notDownloaded:
            return [.download]
        case .queued:
            return [.cancel]
        case .downloading:
            return [.pause, .cancel]
        case .paused:
            return [.resume, .cancel]
        case .failed(.notEnoughSpace, _):
            return [.retry]
        case .failed:
            return [.retry, .cancel]
        case .downloaded:
            return (canRun && !isSelected ? [.use] : []) + [.delete]
        }
    }

    /// True when the screen asks first: the action starts a big download, removes a model, or throws away a download
    /// that has already moved bytes.
    public func needsConfirmation(_ action: Action) -> Bool {
        switch action {
        case .download, .delete: return true
        case .cancel: return receivedBytes > 0
        case .pause, .resume, .retry, .use: return false
        }
    }

    /// Bytes that arrived so far for a model that is not finished.
    public var receivedBytes: Int64 {
        switch state {
        case .downloading(let progress), .paused(let progress), .failed(_, let progress): return progress.receivedBytes
        case .notDownloaded, .queued, .downloaded: return 0
        }
    }

    /// True while bytes are moving or waiting to move.
    public var isBusy: Bool {
        switch state {
        case .queued, .downloading: return true
        case .notDownloaded, .paused, .failed, .downloaded: return false
        }
    }

    /// True when the phone's memory allowance is below the model's estimate, so loading it may fail. Shown as a
    /// caution, not a block: the number is an estimate, and the allowance changes with what else is running.
    public var mayNotFitInMemory: Bool {
        guard let available = availableMemoryBytes else { return false }
        return available < model.estimatedMemoryBytes
    }
}
