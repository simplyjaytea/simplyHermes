import Foundation
import HermesKit
import Testing

private let root = URL(fileURLWithPath: "/containers")

// MARK: - App Group resolution

@Test func declaredGroupIsTheOnlyCandidateWithoutSideStore() {
    #expect(SharedContainer.candidateGroupIDs(infoDictionary: [:]) == [SharedContainer.declaredGroupID])
    #expect(SharedContainer.candidateGroupIDs(infoDictionary: nil) == [SharedContainer.declaredGroupID])
}

@Test func sideStoreRenamedGroupComesFirst() {
    let renamed = SharedContainer.declaredGroupID + ".ABCDE12345"
    let info: [String: Any] = [SharedContainer.sideStoreInfoKey: ["group.other", renamed]]
    #expect(
        SharedContainer.candidateGroupIDs(infoDictionary: info) == [
            renamed, "group.other", SharedContainer.declaredGroupID,
        ])
}

@Test func candidatesHaveNoDuplicates() {
    let info: [String: Any] = [SharedContainer.sideStoreInfoKey: [SharedContainer.declaredGroupID]]
    #expect(SharedContainer.candidateGroupIDs(infoDictionary: info) == [SharedContainer.declaredGroupID])
}

@Test func resolvesTheFirstWritableContainer() {
    let renamed = SharedContainer.declaredGroupID + ".TEAM"
    let info: [String: Any] = [SharedContainer.sideStoreInfoKey: [renamed]]
    let resolution = SharedContainer.resolve(
        infoDictionary: info,
        containerURL: { id in id == SharedContainer.declaredGroupID ? root.appendingPathComponent(id) : nil },
        isWritable: { _ in true }
    )
    let expected = root.appendingPathComponent(SharedContainer.declaredGroupID)
        .appendingPathComponent("Integration", isDirectory: true)
    #expect(resolution == .appGroup(id: SharedContainer.declaredGroupID, directory: expected))
}

@Test func unwritableContainersMeanUnavailable() {
    let resolution = SharedContainer.resolve(
        infoDictionary: nil,
        containerURL: { root.appendingPathComponent($0) },
        isWritable: { _ in false }
    )
    #expect(resolution == .unavailable(tried: [SharedContainer.declaredGroupID]))
    #expect(resolution.directory == nil)
}

@Test func canWriteToATemporaryDirectory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(SharedContainer.canWrite(to: directory))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
}

// MARK: - Widget snapshot

@Test func snapshotRoundTripsThroughTheStore() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = WidgetSnapshotStore(directory: directory)
    #expect(store.load() == nil)

    let snapshot = WidgetSnapshot(
        bots: [
            .init(id: "a", name: "Deploy bot", isActive: true, statusLine: "Running tests"),
            .init(id: "b", name: "Writer", isActive: false, statusLine: "Idle"),
        ],
        approvals: [.init(sessionID: "s1", botName: "Deploy bot", command: "make deploy")],
        updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    try store.save(snapshot)
    #expect(store.load() == snapshot)
    #expect(snapshot.activeBotCount == 1)
}

@Test func snapshotStalenessAndContentComparison() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let fresh = WidgetSnapshot(bots: [], approvals: [], updatedAt: now)
    #expect(!fresh.isStale(at: now.addingTimeInterval(60)))
    #expect(fresh.isStale(at: now.addingTimeInterval(WidgetSnapshot.staleAfter + 1)))

    var later = fresh
    later.updatedAt = now.addingTimeInterval(30)
    #expect(fresh.hasSameContent(as: later))
    later.approvals = [.init(sessionID: "s", botName: "b", command: "c")]
    #expect(!fresh.hasSameContent(as: later))
}
