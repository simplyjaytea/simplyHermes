#if canImport(UIKit)
    import Foundation
    import HermesKit
    import SwiftTerm
    import SwiftUI

    /// What the app sends to the server, in the order the user made it.
    enum TerminalOutbound: Sendable {
        case keys(Data)
        case size(columns: Int, rows: Int)
    }

    /// The ordered queue from the terminal view to the socket. The view yields on the main thread; one task drains
    /// the queue, so keystrokes keep their order.
    final class TerminalOutboundQueue: Sendable {
        let items: AsyncStream<TerminalOutbound>
        private let continuation: AsyncStream<TerminalOutbound>.Continuation

        init() {
            (items, continuation) = AsyncStream<TerminalOutbound>.makeStream()
        }

        func yield(_ item: TerminalOutbound) {
            continuation.yield(item)
        }
    }

    /// One pane's terminal: the view that draws it, the queue of what it sends, and the bytes it is fed.
    @MainActor
    final class TerminalSurface {
        let outbound = TerminalOutboundQueue()
        weak var view: TerminalView?

        /// The window size the view reports, or the standard 80 by 24 before it lays out.
        var size: (columns: Int, rows: Int) {
            guard let terminal = view?.getTerminal() else { return (80, 24) }
            return (terminal.cols, terminal.rows)
        }

        /// Writes server output into the view.
        func feed(_ bytes: Data) {
            view?.feed(byteArray: ArraySlice([UInt8](bytes)))
        }

        /// Queues keys the app generates itself, such as the key row's Escape or Control-C.
        func press(_ bytes: [UInt8]) {
            outbound.yield(.keys(Data(bytes)))
        }

        /// Queues an arrow key in the sequence the running program expects: `SS3` in application cursor mode, `CSI`
        /// otherwise.
        func pressArrow(_ letter: Character) {
            let applicationMode = view?.getTerminal().applicationCursor ?? false
            press(Array((applicationMode ? "\u{1B}O" : "\u{1B}[").utf8) + Array(String(letter).utf8))
        }

        /// The text on screen, one string per row, with trailing spaces removed.
        func screenLines() -> [String] {
            guard let terminal = view?.getTerminal() else { return [] }
            return (0..<terminal.rows).map { row in
                terminal.getLine(row: row)?.translateToString(trimRight: true) ?? ""
            }
        }
    }

    /// Relays what the terminal view emits to the outbound queue. SwiftTerm calls these on the main thread; the
    /// queue is thread-safe, so the methods need no actor.
    final class TerminalSurfaceCoordinator: NSObject, TerminalViewDelegate {
        private let outbound: TerminalOutboundQueue
        var appliedDark: Bool?

        init(outbound: TerminalOutboundQueue) {
            self.outbound = outbound
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            outbound.yield(.keys(Data(data)))
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            outbound.yield(.size(columns: newCols, rows: newRows))
        }

        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func clipboardRead(source: TerminalView) -> Data? { nil }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    /// The SwiftTerm view for one pane. It takes its palette from the appearance and reports keys and size to the
    /// surface's queue.
    struct TerminalSurfaceView: UIViewRepresentable {
        let surface: TerminalSurface
        let isDark: Bool

        func makeCoordinator() -> TerminalSurfaceCoordinator {
            TerminalSurfaceCoordinator(outbound: surface.outbound)
        }

        func makeUIView(context: Context) -> TerminalView {
            let view = TerminalView(frame: .zero)
            view.terminalDelegate = context.coordinator
            TerminalPalette.apply(to: view, dark: isDark)
            context.coordinator.appliedDark = isDark
            surface.view = view
            return view
        }

        func updateUIView(_ view: TerminalView, context: Context) {
            // Re-applying the palette resets the font and colors, so do it only when the appearance changes.
            guard context.coordinator.appliedDark != isDark else { return }
            context.coordinator.appliedDark = isDark
            TerminalPalette.apply(to: view, dark: isDark)
        }
    }
#endif
