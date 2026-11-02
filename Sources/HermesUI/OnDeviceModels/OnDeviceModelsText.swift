#if canImport(UIKit)
    import Foundation
    import HermesKit

    /// The words on Settings > On-device models. Plain sentences, no jargon.
    enum OnDeviceModelsText {
        static func size(_ bytes: Int64) -> String {
            bytes.formatted(.byteCount(style: .file))
        }

        static func percent(_ progress: OnDeviceModelProgress) -> String {
            progress.fraction.formatted(.percent.precision(.fractionLength(0)))
        }

        // MARK: Rows

        /// "1.2 GB download" before, "1.2 GB on this device" after. The memory figure is the estimate the app uses.
        static func sizeLine(_ row: OnDeviceModelRow) -> String {
            let total = size(row.model.totalBytes)
            if case .downloaded = row.state { return "\(total) on this device" }
            return "\(total) download. Needs about \(size(row.model.estimatedMemoryBytes)) of memory to run."
        }

        /// The terms the weights come under, from the catalog.
        static func licenseLine(_ model: OnDeviceModel) -> String {
            "License: \(model.license)."
        }

        static func memoryCaution(_ row: OnDeviceModelRow) -> String {
            guard let available = row.availableMemoryBytes else { return "" }
            return "This device allows about \(size(available)) for apps right now. The model may not load."
        }

        static func label(for action: OnDeviceModelRow.Action, row: OnDeviceModelRow) -> String {
            switch action {
            case .download: return "Download"
            case .pause: return "Pause"
            case .resume: return "Resume"
            case .retry: return "Try again"
            case .check: return "Check again"
            case .cancel:
                switch row.state {
                case .paused, .failed: return "Discard"
                default: return "Cancel"
                }
            case .delete: return "Delete"
            case .use: return "Use this model"
            }
        }

        /// Buttons say what they do. The model name makes each one distinct for VoiceOver.
        static func accessibilityLabel(for action: OnDeviceModelRow.Action, row: OnDeviceModelRow) -> String {
            let name = row.model.displayName
            let verb = label(for: action, row: row)
            if action == .download { return "\(verb) \(name), \(size(row.model.totalBytes))" }
            return "\(verb) \(name)"
        }

        static func statusLine(_ row: OnDeviceModelRow) -> String? {
            switch row.state {
            case .notDownloaded: return nil
            case .checking: return "Checking files from an earlier download."
            case .queued where row.isRepairing, .downloading where row.isRepairing, .paused where row.isRepairing:
                // The same wording as a file that fails after a download: the file was removed, and it is fetched again.
                return failureText(.damaged(file: ""))
            case .queued: return "Waiting for the download in front of it."
            case .downloading(let progress):
                return "\(size(progress.receivedBytes)) of \(size(progress.totalBytes))"
            case .paused(let progress): return "Paused at \(percent(progress))."
            case .failed(let failure, _): return failureText(failure)
            case .downloaded: return nil
            }
        }

        static func failureText(_ failure: OnDeviceModelFailure) -> String {
            switch failure {
            case .notEnoughSpace(let needed, let available):
                return "Not enough room. It needs \(size(needed)) free, and \(size(available)) is free."
            case .network:
                return "The connection dropped. Try again to continue."
            case .server(let status):
                return "The download server answered with error \(status). Try again later."
            case .damaged:
                return "A file didn't match its checksum and was removed. Download again."
            case .storage:
                return "This device could not save the file. Free some space and try again."
            case .checkFailed:
                return
                    "A file could not be read, so the download could not be checked. Check again, or delete the model."
            }
        }

        // MARK: Apple model

        static func appleDetail(_ availability: LocalModelAvailability) -> String {
            switch availability {
            case .available: return "Built into iOS. Nothing to download."
            case .unavailable(.unsupported): return "This device does not support Apple Intelligence."
            case .unavailable(.disabled):
                return "Apple Intelligence is off. Turn it on in the Settings app to use this model."
            case .unavailable(.noModelChosen): return "No on-device model is in use."
            case .unavailable(.notReady): return "The model is still getting ready. Try again in a few minutes."
            case .unavailable(.switchedOff): return "On-device features are switched off above."
            }
        }

        // MARK: Questions

        static func title(for question: OnDeviceModelsModel.Question) -> String {
            switch question.action {
            case .download: return "Download \(question.model.displayName)?"
            case .delete: return "Delete \(question.model.displayName)?"
            default: return "Discard the download?"
            }
        }

        static func message(for question: OnDeviceModelsModel.Question) -> String {
            let model = question.model
            switch question.action {
            case .download:
                return
                    "\(size(model.totalBytes)) will be downloaded to this device, so Wi-Fi is best. "
                    + "You can pause it and delete the model at any time."
            case .delete:
                guard let bytes = question.freedBytes else {
                    return "This deletes \(model.displayName) from this iPhone. You can download it again later."
                }
                return "This frees \(size(bytes)). You can download it again later."
            default:
                return "The \(size(question.receivedBytes)) that arrived will be deleted."
            }
        }

        static func confirmLabel(for question: OnDeviceModelsModel.Question) -> String {
            switch question.action {
            case .download: return "Download \(size(question.model.totalBytes))"
            case .delete: return "Delete"
            default: return "Discard"
            }
        }

        // MARK: Notes

        /// Under the model list: what changed after a memory warning, or why nothing can be picked.
        /// Shown when the model in use was deleted. Nothing answers on the device until the user picks one.
        static let noModelInUse = "No on-device model is in use. Pick one below to answer on this iPhone."

        static func footer(suspended: Bool, canRun: Bool) -> String {
            var lines: [String] = []
            if suspended {
                lines.append(
                    "The device ran low on memory, so the Apple model is answering for now. "
                        + "Choose Use this model to switch back.")
            } else if !canRun {
                lines.append("This device cannot run downloaded models. You can still download and delete them.")
            }
            lines.append("Models come from Hugging Face and stay on this device. They are not backed up.")
            return lines.joined(separator: " ")
        }
    }
#endif
