import Foundation
import HermesKit
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
}

@Suite struct ShareOutboxTests {
    // MARK: Payload encoding

    @Test func payloadSurvivesEncodingAndDecoding() throws {
        let payload = SharePayload(
            id: "abc-123", createdAt: now, destination: .chat(sessionID: "20261014_032737_07e33f"),
            text: "Look at this\n\nhttps://example.com",
            attachments: [
                .init(kind: .image, fileName: "Photo 1.jpg", storedName: "1-Photo 1.jpg", byteCount: 1200),
                .init(kind: .pdf, fileName: "report.pdf", storedName: "2-report.pdf", byteCount: 5000),
            ])
        let decoded = try JSONDecoder().decode(SharePayload.self, from: JSONEncoder().encode(payload))
        #expect(decoded == payload)

        let newChat = SharePayload(id: "x", createdAt: now, destination: .newChat, text: "hello")
        #expect(try JSONDecoder().decode(SharePayload.self, from: JSONEncoder().encode(newChat)) == newChat)
        #expect(newChat.attachments.isEmpty)
    }

    @Test func attachmentsBecomeComposerAttachments() {
        let photo = SharePayload.Attachment(
            kind: .image, fileName: "Photo 1.jpg", storedName: "1-Photo 1.jpg", byteCount: 3)
        let attachment = photo.composerAttachment(data: Data([1, 2, 3]))
        #expect(attachment.kind == .image && attachment.name == "Photo 1.jpg" && attachment.data == Data([1, 2, 3]))
        let pdf = SharePayload.Attachment(kind: .pdf, fileName: "a.pdf", storedName: "2-a.pdf", byteCount: 1)
        #expect(pdf.composerAttachment(data: Data()).kind == .pdf)
        let file = SharePayload.Attachment(kind: .file, fileName: "a.zip", storedName: "3-a.zip", byteCount: 1)
        #expect(file.composerAttachment(data: Data()).kind == .file)
        #expect(SharePayload.Attachment.Kind.forFile(named: "Report.PDF") == .pdf)
        #expect(SharePayload.Attachment.Kind.forFile(named: "notes.txt") == .file)
    }

    // MARK: Outbox folders

    @Test func sharesTravelThroughTheOutbox() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = ShareOutbox(directory: directory)
        let id = ShareOutbox.makeID()
        try outbox.prepare(id: id)

        let photo = try outbox.storeData(
            id: id, data: Data(repeating: 7, count: 10), fileName: "Photo 1.jpg", kind: .image)
        #expect(photo.storedName == "1-Photo 1.jpg" && photo.fileName == "Photo 1.jpg" && photo.byteCount == 10)

        let source = directory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: source)
        let file = try outbox.storeFile(id: id, copying: source, fileName: "notes.txt", kind: .file)
        #expect(file.storedName == "2-notes.txt" && file.byteCount == 5 && file.kind == .file)

        #expect(outbox.pending().isEmpty, "a share without payload.json is still being built")
        let payload = SharePayload(
            id: id, createdAt: now, destination: .newChat, text: "hi", attachments: [photo, file])
        try outbox.commit(payload)
        #expect(outbox.pending() == [payload])
        #expect(outbox.payload(id: id) == payload)
        #expect(outbox.data(of: file, in: id) == Data("hello".utf8))
        #expect(outbox.data(of: photo, in: id) == Data(repeating: 7, count: 10))

        outbox.remove(id: id)
        #expect(outbox.pending().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: outbox.folder(for: id).path))
    }

    @Test func aShareKeptAsDraftKeepsItsFilesUntilItIsRemoved() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = ShareOutbox(directory: directory)
        let id = ShareOutbox.makeID()
        try outbox.prepare(id: id)
        let photo = try outbox.storeData(id: id, data: Data([1, 2, 3]), fileName: "Photo.jpg", kind: .image)
        try outbox.commit(
            SharePayload(id: id, createdAt: now, destination: .newChat, text: "note", attachments: [photo]))
        #expect(outbox.pending().map(\.keptAsDraft) == [false], "a share is sent unless it was kept as a draft")

        #expect(outbox.markKeptAsDraft(id: id))
        #expect(outbox.pending().map(\.keptAsDraft) == [true], "the next launch puts it back as a draft")
        #expect(outbox.data(of: photo, in: id) == Data([1, 2, 3]), "the photo is still there for that")

        outbox.remove(id: id)
        #expect(outbox.pending().isEmpty)
        #expect(!outbox.markKeptAsDraft(id: id), "a removed share cannot be marked")
    }

    @Test func pendingSharesComeOldestFirst() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = ShareOutbox(directory: directory)
        let later = SharePayload(id: "b", createdAt: now.addingTimeInterval(60), destination: .newChat, text: "second")
        let earlier = SharePayload(id: "c", createdAt: now, destination: .newChat, text: "first")
        for payload in [later, earlier] {
            try outbox.prepare(id: payload.id)
            try outbox.commit(payload)
        }
        #expect(outbox.pending().map(\.text) == ["first", "second"])
    }

    @Test func aDamagedPayloadIsNotPending() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = ShareOutbox(directory: directory)
        try outbox.prepare(id: "broken")
        try Data("{not json".utf8).write(to: outbox.folder(for: "broken").appendingPathComponent("payload.json"))
        #expect(outbox.pending().isEmpty && outbox.payload(id: "broken") == nil)
    }

    @Test func aPayloadMustMatchItsFolder() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = ShareOutbox(directory: directory)
        try outbox.prepare(id: "one")
        try outbox.commit(SharePayload(id: "one", createdAt: now, destination: .newChat, text: "hi"))
        try FileManager.default.moveItem(at: outbox.folder(for: "one"), to: outbox.folder(for: "two"))
        #expect(outbox.payload(id: "two") == nil, "the id inside payload.json must equal the folder name")
    }

    @Test func unsafeIdsAndNamesAreRefused() throws {
        let outbox = ShareOutbox(directory: temporaryDirectory())
        #expect(throws: ShareOutboxError.invalidID) { try outbox.prepare(id: "../escape") }
        #expect(throws: ShareOutboxError.invalidID) {
            try outbox.commit(SharePayload(id: "a/b", createdAt: now, destination: .newChat, text: ""))
        }
        let attachment = SharePayload.Attachment(kind: .file, fileName: "x", storedName: "../../secret", byteCount: 1)
        #expect(outbox.data(of: attachment, in: "ok") == nil)
        #expect(outbox.data(of: .init(kind: .file, fileName: "x", storedName: "..", byteCount: 1), in: "ok") == nil)
    }

    @Test func idsAreSafeFolderNames() {
        let good = ["abc", "A-b_9", ShareOutbox.makeID(), String(repeating: "a", count: 64)]
        for id in good { #expect(ShareOutbox.isValidID(id), "\(id)") }
        let bad = ["", "..", "a/b", "a b", "é", "a.b", String(repeating: "a", count: 65)]
        for id in bad { #expect(!ShareOutbox.isValidID(id), "\(id)") }
    }

    @Test func fileNamesLoseFoldersAndOddCharacters() {
        #expect(ShareOutbox.safeFileName("../../etc/passwd") == "passwd")
        #expect(ShareOutbox.safeFileName("a\\b\\c.txt") == "c.txt")
        #expect(ShareOutbox.safeFileName(".hidden") == "hidden")
        #expect(ShareOutbox.safeFileName("  notes.txt ") == "notes.txt")
        #expect(ShareOutbox.safeFileName("a\u{0}b.txt") == "ab.txt")
        #expect(ShareOutbox.safeFileName("") == "file")
        #expect(ShareOutbox.safeFileName("///") == "file")
        #expect(ShareOutbox.safeFileName("...") == "file")
        #expect(ShareOutbox.safeFileName("", fallback: "Photo") == "Photo")
        let long = ShareOutbox.safeFileName(String(repeating: "a", count: 200) + ".pdf")
        #expect(long.count == ShareOutbox.maxFileNameLength && long.hasSuffix(".pdf"))
        #expect(ShareOutbox.safeFileName(String(repeating: "b", count: 200)).count == ShareOutbox.maxFileNameLength)
    }

    @Test func purgeDropsOldAndAbandonedShares() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = ShareOutbox(directory: directory)
        let base = Date()
        try outbox.prepare(id: "fresh")
        try outbox.commit(SharePayload(id: "fresh", createdAt: base, destination: .newChat, text: "keep"))
        try outbox.prepare(id: "old")
        let eightDaysAgo = base.addingTimeInterval(-8 * 24 * 3600)
        try outbox.commit(SharePayload(id: "old", createdAt: eightDaysAgo, destination: .newChat, text: "drop"))
        try outbox.prepare(id: "abandoned")
        _ = try outbox.storeData(id: "abandoned", data: Data([1]), fileName: "a.bin", kind: .file)

        outbox.purge(now: base)
        #expect(outbox.pending().map(\.id) == ["fresh"], "committed shares are judged by their own date")
        #expect(
            FileManager.default.fileExists(atPath: outbox.folder(for: "abandoned").path), "a new unfinished share stays"
        )

        outbox.purge(now: base.addingTimeInterval(2 * 24 * 3600))
        #expect(!FileManager.default.fileExists(atPath: outbox.folder(for: "abandoned").path))
        #expect(outbox.pending().map(\.id) == ["fresh"])
    }

    // MARK: Limits

    @Test func budgetStopsAtTheCountAndTheSizeLimit() {
        var budget = ShareBudget()
        let first = budget.admit(byteCount: 20 * 1024 * 1024)
        let tooBig = budget.admit(byteCount: 6 * 1024 * 1024)
        let countAfterRefusal = budget.count
        let exact = budget.admit(byteCount: 5 * 1024 * 1024)
        let over = budget.admit(byteCount: 1)
        #expect(first == nil && tooBig == .tooLarge)
        #expect(countAfterRefusal == 1, "a refused file is not counted")
        #expect(exact == nil, "exactly at the limit still fits")
        #expect(over == .tooLarge)

        var many = ShareBudget()
        let results = (0...ShareLimits.maxAttachments).map { _ in many.admit(byteCount: 10) }
        #expect(results.dropLast().allSatisfy { $0 == nil })
        #expect(results.last == .tooMany)
    }

    @Test func oneFileCannotBeBiggerThanTheComposerSends() {
        var budget = ShareBudget()
        let tooBig = budget.admit(byteCount: ShareLimits.maxFileBytes + 1)
        let countAfterRefusal = budget.count
        let exact = budget.admit(byteCount: ShareLimits.maxFileBytes)
        #expect(ShareLimits.maxFileBytes == ComposerAttachment.maxBytes)
        #expect(tooBig == .fileTooLarge && countAfterRefusal == 0)
        #expect(exact == nil)
    }

    @Test func refusalNoticesNameTheFileAndTheLimit() {
        let large = ShareBudget.notice(for: .tooLarge, fileName: "movie.mov")
        #expect(large.contains("movie.mov") && large.contains("\(ShareLimits.maxTotalMegabytes) MB"))
        let single = ShareBudget.notice(for: .fileTooLarge, fileName: "disk.img")
        #expect(single.contains("disk.img") && single.contains("\(ShareLimits.maxFileMegabytes) MB"))
        let many = ShareBudget.notice(for: .tooMany, fileName: "6.txt")
        #expect(many.contains("6.txt") && many.contains("\(ShareLimits.maxAttachments)"))
        #expect(ShareLimits.summary.contains("2048") && ShareLimits.summary.contains("25 MB"))
        #expect(ShareLimits.summary.contains("20 MB"))
        #expect(ShareBudget.overflowNotice(leftOut: 1).hasPrefix("1 more file was left out"))
        #expect(ShareBudget.overflowNotice(leftOut: 7).hasPrefix("7 more files were left out"))
    }

    // MARK: Message

    @Test func theMessageJoinsNoteTextAndLinks() {
        let message = ShareMessage.compose(
            note: " Read this ", texts: ["An article"], urls: [URL(string: "https://example.com/a")!])
        #expect(message == "Read this\n\nAn article\n\nhttps://example.com/a")
    }

    @Test func linksAlreadyInTheTextAreNotRepeated() {
        let url = URL(string: "https://example.com/a")!
        #expect(
            ShareMessage.compose(note: "", texts: ["See https://example.com/a now"], urls: [url])
                == "See https://example.com/a now")
        #expect(ShareMessage.compose(note: "same", texts: ["same", "  "], urls: []) == "same")
        #expect(ShareMessage.compose(note: "", texts: [], urls: []).isEmpty)
    }

    @Test func longTextIsCut() {
        let message = ShareMessage.compose(
            note: "", texts: [String(repeating: "x", count: ShareLimits.maxTextCharacters + 10)], urls: [])
        #expect(message.count == ShareLimits.maxTextCharacters)
    }

    @Test func aShareNeedsTextOrAFile() {
        #expect(!ShareMessage.hasContent(message: " \n", attachmentCount: 0))
        #expect(ShareMessage.hasContent(message: "hi", attachmentCount: 0))
        #expect(ShareMessage.hasContent(message: "", attachmentCount: 1))
    }

    @Test func theConfirmedSharePutsItAllInOnePayload() {
        let file = SharePayload.Attachment(kind: .pdf, fileName: "a.pdf", storedName: "1-a.pdf", byteCount: 10)
        let content = ShareContent(
            note: "For later", texts: ["Some text"], urls: [URL(string: "https://example.com")!], attachments: [file])
        let payload = content.payload(id: "abc", createdAt: now, destination: .chat(sessionID: "s1"))
        #expect(payload.id == "abc" && payload.createdAt == now)
        #expect(payload.destination == .chat(sessionID: "s1"))
        #expect(payload.text == "For later\n\nSome text\n\nhttps://example.com")
        #expect(payload.attachments == [file])
    }

    @Test func sharedContentCanBeSentWhenItHoldsAnythingAtAll() {
        let link = URL(string: "https://example.com")!
        let file = SharePayload.Attachment(kind: .file, fileName: "a.zip", storedName: "1-a.zip", byteCount: 10)
        #expect(!ShareContent(texts: [], urls: [], attachments: []).hasContent)
        #expect(!ShareContent(note: "  ", texts: [" \n"], urls: [], attachments: []).hasContent)
        #expect(ShareContent(texts: ["hello"], urls: [], attachments: []).hasContent)
        #expect(ShareContent(texts: [], urls: [link], attachments: []).hasContent)
        #expect(ShareContent(texts: [], urls: [], attachments: [file]).hasContent)
        #expect(ShareContent(note: "Look at this", texts: [], urls: [], attachments: []).message == "Look at this")
    }

    // MARK: Destinations

    @Test func newChatComesFirstThenRecentChats() {
        let recent = RecentChatsSnapshot(
            chats: [
                RecentChat(id: "s1", title: "Backup cron fix", subtitle: "14:05"),
                RecentChat(id: "s2", title: "", subtitle: ""),
            ], updatedAt: now)
        let list = ShareDestination.list(recent: recent)
        #expect(list.map(\.title) == ["New chat", "Backup cron fix", "Untitled chat"])
        #expect(list.map(\.subtitle) == [nil, "14:05", nil])
        #expect(list[0].destination == .newChat && list[1].destination == .chat(sessionID: "s1"))
        #expect(Set(list.map(\.id)).count == list.count)
    }

    @Test func withoutASnapshotOnlyNewChatIsOffered() {
        #expect(ShareDestination.list(recent: nil) == [ShareDestination.newChat])
    }

    @Test func theRecentListKeepsTheFirstChatsAndRoundTrips() throws {
        let chats = (1...15).map { RecentChat(id: "s\($0)", title: "Chat \($0)") }
        let snapshot = RecentChatsSnapshot(chats: chats, updatedAt: now)
        #expect(snapshot.chats.count == RecentChatsSnapshot.limit && snapshot.chats.first?.id == "s1")

        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecentChatsSnapshot.store(directory: directory)
        #expect(store.load() == nil)
        try store.save(snapshot)
        #expect(store.load() == snapshot)
        #expect(snapshot.hasSameContent(as: RecentChatsSnapshot(chats: chats, updatedAt: now.addingTimeInterval(5))))
    }

    @Test func aLongerRecentListCanBeAsked() {
        let chats = (1...15).map { RecentChat(id: "s\($0)", title: "Chat \($0)") }
        #expect(RecentChatsSnapshot(chats: chats, updatedAt: now, limit: 12).chats.count == 12)
        #expect(RecentChatsSnapshot(chats: chats, updatedAt: now, limit: 99).chats.count == 15)
        #expect(RecentChatsSnapshot(chats: chats, updatedAt: now, limit: -1).chats.isEmpty)
    }
}
