import CoreSpotlight
import Foundation
import HermesKit
import OSLog
import UniformTypeIdentifiers

/// Puts chat titles and bot names into Spotlight, so searching for "deploy script" finds that chat.
///
/// What goes in, and what changed since last time, is decided by ``SpotlightPlanner``; this type only sends the plan to
/// CoreSpotlight. Updates are debounced, so a burst of changes (the chat list refreshing) becomes one call. Message
/// text is never indexed.
@MainActor
final class SpotlightIndexer {
    /// How long changes settle before they are sent.
    private let settleTime: Duration = .seconds(2)

    private let index: CSSearchableIndex
    private let store: JSONFileStore<SpotlightIndexState>
    private var state: SpotlightIndexState
    private var needsCleanSlate: Bool
    private var chats: [SpotlightChat] = []
    private var bots: [SpotlightBot] = []
    private var pending: Task<Void, Never>?
    private var isSending = false
    private let logger = Logger(subsystem: "com.simplyjaytea.simplyhermes", category: "Spotlight")

    init(directory: URL, index: CSSearchableIndex = .default()) {
        self.index = index
        store = SpotlightIndexState.store(directory: directory)
        let saved = store.load()
        state = saved ?? SpotlightIndexState()
        // With no saved state (first run, or the app was reinstalled) older entries may linger, so start clean.
        needsCleanSlate = saved == nil
    }

    /// The chats the server lists, newest first. Call with the full list each time it changes.
    func update(chats: [SpotlightChat]) {
        guard chats != self.chats else { return }
        self.chats = chats
        schedule()
    }

    func update(bots: [SpotlightBot]) {
        guard bots != self.bots else { return }
        self.bots = bots
        schedule()
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            guard let delay = self?.settleTime else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.send()
        }
    }

    private func send() async {
        guard !isSending else {
            schedule()
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            if needsCleanSlate {
                try await deleteEverything()
                needsCleanSlate = false
            }
            let plan = SpotlightPlanner.plan(chats: chats, bots: bots, indexed: state)
            guard !plan.isEmpty else { return }
            if !plan.deletions.isEmpty { try await delete(plan.deletions) }
            if !plan.upserts.isEmpty { try await add(plan.upserts) }
            state = SpotlightPlanner.applying(plan, to: state)
            try store.save(state)
        } catch {
            // The state did not move on, so the next update plans the same work again.
            logger.error("Spotlight update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: CoreSpotlight

    private func add(_ items: [SpotlightItem]) async throws {
        let searchable = items.map(Self.searchableItem)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            index.indexSearchableItems(searchable) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func delete(_ identifiers: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            index.deleteSearchableItems(withIdentifiers: identifiers) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func deleteEverything() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            index.deleteAllSearchableItems { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func searchableItem(_ item: SpotlightItem) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = item.title
        attributes.contentDescription = item.detail
        attributes.keywords = item.keywords
        let searchable = CSSearchableItem(
            uniqueIdentifier: item.identifier, domainIdentifier: item.domain, attributeSet: attributes)
        // The default expiry is 30 days. The planner sends only changes, so an entry must not expire on its own.
        searchable.expirationDate = .distantFuture
        return searchable
    }
}
