import HermesKit
import HermesUI
import SwiftUI
import UIKit

/// The Share extension: "Send to Hermes" in the iOS share sheet.
///
/// It reads what was shared, lets the user pick a chat and add a note, and writes the result to the outbox in the
/// shared container. Then it opens simplyHermes at `simplyhermes://share/<id>`, and the app sends the message. The
/// extension never opens a connection to a server and holds no secrets. If the app cannot be opened from here, the
/// share waits in the outbox and the app sends it the next time it becomes active.
final class ShareViewController: UIViewController {
    private let flow = ShareFlow()
    private let shareID = ShareOutbox.makeID()
    private var outbox: ShareOutbox?
    private var model: ShareSheetModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        outbox = ShareStorage.directory.map(ShareOutbox.init(directory:))

        let root = ShareRootView(
            flow: flow,
            onCancel: { [weak self] in self?.cancel() },
            onSend: { [weak self] in self?.send() },
            onDone: { [weak self] in self?.finish() })
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        Task { await self.prepare() }
    }

    // MARK: Reading what was shared

    private func prepare() async {
        let recent = ShareStorage.directory.flatMap { RecentChatsSnapshot.store(directory: $0).load() }
        guard let outbox, (try? outbox.prepare(id: shareID)) != nil else {
            flow.phase = .ready(unavailableModel())
            return
        }
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let loader = ShareItemLoader(outbox: outbox, shareID: shareID)
        var texts: [String] = []
        var urls: [URL] = []
        var files: [SharePayload.Attachment] = []
        var notices: [String] = []
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            switch await loader.load(provider) {
            case .text(let text): texts.append(text)
            case .link(let url): urls.append(url)
            case .file(let attachment): files.append(attachment)
            case .refused(let notice): notices.append(notice)
            case .skipped: break
            }
        }
        if loader.filesLeftOut > 0 {
            notices.append(ShareBudget.overflowNotice(leftOut: loader.filesLeftOut))
        }
        // A web page arrives as a link; the page title is a useful line to send with it.
        if texts.isEmpty, !urls.isEmpty {
            texts = items.compactMap { $0.attributedContentText?.string }
        }
        let model = ShareSheetModel(
            texts: texts, urls: urls, attachments: files, destinations: ShareDestination.list(recent: recent),
            notices: notices)
        self.model = model
        flow.phase = .ready(model)
    }

    private func unavailableModel() -> ShareSheetModel {
        ShareSheetModel(
            texts: [], urls: [], attachments: [], destinations: [.newChat], isUnavailable: true)
    }

    // MARK: Actions

    private func send() {
        guard let outbox, let model, model.canSend else { return }
        model.isSending = true
        do {
            try outbox.commit(model.payload(id: shareID, now: Date()))
        } catch {
            model.isSending = false
            flow.problem = "simplyHermes could not save this share. Try again."
            return
        }
        if openApp(at: HermesURL.share(shareID)) {
            finish()
        } else {
            flow.phase = .savedForLater
        }
    }

    private func cancel() {
        outbox?.remove(id: shareID)
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Opens simplyHermes. `NSExtensionContext.open` only works for Today widgets, so this asks the responder chain
    /// for `UIApplication`'s own `open` method by name. It returns whether a responder was found, not whether iOS
    /// agreed to switch apps: when it does not, the share still waits in the outbox for the next time the app opens.
    private func openApp(at url: URL) -> Bool {
        typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                let function = unsafeBitCast(current.method(for: selector), to: OpenURL.self)
                function(current, selector, url as NSURL, [:] as NSDictionary, nil)
                return true
            }
            responder = current.next
        }
        return false
    }
}
