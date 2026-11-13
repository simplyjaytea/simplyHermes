import Foundation

/// A chat's attach, as the steps that make it, with a check after every one (board row 140).
///
/// An attach awaits several times: for the client, for the profile, for the session. The user can switch servers during
/// any of them. A check only at the start lets the attach finish against the wrong server and then drain the outbox
/// there. So the attach is a list of steps, and before the first step and after each one this asks the caller whether the
/// attach is still wanted. When it is not (the chat was retired, another server is active now, or the task was
/// cancelled), the steps already done are rolled back, in reverse, and nothing after them runs. The caller commits the
/// attach (sets its controller, starts following, drains) as the last step, which has no await of its own, so the last
/// check and the commit cannot be split by a switch.
@MainActor
public enum ChatAttach {
    /// One step: what it does, and how to undo it if a later check says the attach is no longer wanted.
    public struct Step {
        public let name: String
        public let run: @MainActor () async throws -> Void
        public let rollback: @MainActor () async -> Void

        public init(
            _ name: String, run: @escaping @MainActor () async throws -> Void,
            rollback: @escaping @MainActor () async -> Void = {}
        ) {
            self.name = name
            self.run = run
            self.rollback = rollback
        }
    }

    public enum Outcome: Equatable, Sendable {
        /// Every step ran and the attach was still wanted after each.
        case attached
        /// The attach stopped, and what it had done was rolled back. `step` is the one after which the check failed, or
        /// nil when it was already unwanted at the start.
        case abandoned(step: String?)
    }

    /// Runs `steps` in order. A step that throws is rolled back with the steps before it, and the error is rethrown.
    public static func run(_ steps: [Step], stillWanted: @MainActor () -> Bool) async throws -> Outcome {
        guard isWanted(stillWanted) else { return .abandoned(step: nil) }
        var done: [Step] = []
        for step in steps {
            done.append(step)
            do {
                try await step.run()
            } catch {
                await rollBack(done)
                throw error
            }
            guard isWanted(stillWanted) else {
                await rollBack(done)
                return .abandoned(step: step.name)
            }
        }
        return .attached
    }

    private static func isWanted(_ stillWanted: @MainActor () -> Bool) -> Bool {
        !Task.isCancelled && stillWanted()
    }

    private static func rollBack(_ done: [Step]) async {
        for step in done.reversed() { await step.rollback() }
    }
}
