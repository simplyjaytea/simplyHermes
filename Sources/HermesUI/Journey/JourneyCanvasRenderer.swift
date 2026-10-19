#if canImport(UIKit)
    import HermesKit
    import SwiftUI

    /// What the graph canvas draws, as plain values. The canvas closure captures only this, so drawing never touches the
    /// model.
    struct JourneyCanvasInput: Sendable, Equatable {
        /// The nodes and links on screen, in layout space.
        var scene: JourneyScene
        /// Zoom and pan.
        var viewport: JourneyViewport
        /// The node whose sheet is open.
        var selectedID: String?
        /// True when every node gets its name under it.
        var showsLabels: Bool
    }

    /// Draws the memory graph into a canvas: links first, then one mark per node.
    ///
    /// Shape and brightness carry meaning as well as colour, so the graph reads without colour vision: a memory chunk is
    /// a rounded square and a skill is a circle; a ring marks a skill the agent wrote itself; a white dot marks a pinned
    /// skill; an archived or stale skill is fainter and smaller.
    enum JourneyCanvasRenderer {
        /// How far past the view edge a node is still drawn, so half-hidden marks do not pop in.
        private static let margin: CGFloat = 40

        static func draw(_ input: JourneyCanvasInput, in context: inout GraphicsContext, size: CGSize) {
            let viewport = input.viewport
            var links = Path()
            for link in input.scene.links {
                links.move(to: viewport.toView(link.source, in: size))
                links.addLine(to: viewport.toView(link.target, in: size))
            }
            context.stroke(links, with: .color(HermesColor.secondaryText.opacity(0.35)), lineWidth: 1)

            let visible = CGRect(origin: .zero, size: size).insetBy(dx: -margin, dy: -margin)
            for node in input.scene.nodes {
                let center = viewport.toView(node.position, in: size)
                guard visible.contains(center) else { continue }
                drawMark(of: node, at: center, isSelected: node.id == input.selectedID, in: &context)
            }
            for node in input.scene.nodes where input.showsLabels || node.id == input.selectedID {
                let center = viewport.toView(node.position, in: size)
                guard visible.contains(center) else { continue }
                let below = CGPoint(x: center.x, y: center.y + CGFloat(node.radius) + 4)
                context.draw(Text(node.label).font(HermesFont.caption2), at: below, anchor: .top)
            }
        }

        private static func drawMark(
            of node: JourneyScene.Node, at center: CGPoint, isSelected: Bool, in context: inout GraphicsContext
        ) {
            let color = JourneyPalette.color(slot: node.paletteIndex)
            let radius = CGFloat(node.radius)
            let box = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let isMemory = node.kind == .memory
            context.fill(shape(in: box, isMemory: isMemory), with: .color(color.opacity(node.isDimmed ? 0.4 : 1)))
            if node.isLearned {
                let ring = shape(in: box.insetBy(dx: -3.5, dy: -3.5), isMemory: isMemory)
                context.stroke(ring, with: .color(color.opacity(0.75)), lineWidth: 1.5)
            }
            if node.isPinned {
                let dot = box.insetBy(dx: radius * 0.55, dy: radius * 0.55)
                context.fill(Path(ellipseIn: dot), with: .color(HermesColor.onAccent.opacity(0.9)))
            }
            if isSelected {
                let ring = box.insetBy(dx: -7, dy: -7)
                context.stroke(Path(ellipseIn: ring), with: .color(HermesColor.accent), lineWidth: 3)
            }
        }

        private static func shape(in box: CGRect, isMemory: Bool) -> Path {
            isMemory ? Path(roundedRect: box, cornerRadius: box.width * 0.3) : Path(ellipseIn: box)
        }
    }
#endif
