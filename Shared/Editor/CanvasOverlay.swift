import SwiftUI

/// What the tool in hand is doing, drawn over the picture: the selection's
/// marching ants, the outline of the layer being moved, a shape being
/// dragged out, the crop frame.
struct CanvasOverlay: View {
    let composition: Composition
    let state: EditorState
    let viewport: CanvasViewport

    var body: some View {
        // The ants march only while there is a selection to show.
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !hasSelection)) { timeline in
            Canvas { context, _ in
                let phase = timeline.date.timeIntervalSinceReferenceDate * 12
                draw(in: &context, antsPhase: phase)
            }
        }
    }

    private var hasSelection: Bool {
        state.selection != nil || state.draftSelection != nil
    }

    private func draw(in context: inout GraphicsContext, antsPhase: Double) {
        let transform = viewport.transform

        if state.tool == .move || state.tool == .text, let layer = state.activeLayer, layer.isVisible {
            var outline = Path()
            outline.addLines(layer.corners.map { $0.applying(transform) })
            outline.closeSubpath()
            context.stroke(outline, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }

        for selection in [state.selection, state.draftSelection].compactMap({ $0 }) {
            let path = Path(selection.path(in: composition.size)).applying(transform)
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1))
            context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 1, dash: [5, 5], dashPhase: antsPhase))
        }

        if let shape = state.draftShape {
            let path = Path(shape.path).applying(transform)
            if shape.fills {
                context.fill(path, with: .color(shape.color.color))
            } else {
                context.stroke(path, with: .color(shape.color.color), style: StrokeStyle(
                    lineWidth: shape.lineWidth * viewport.scale, lineCap: .round, lineJoin: .round
                ))
            }
        }

        if let gradient = state.draftGradient {
            let start = gradient.start.applying(transform)
            let end = gradient.end.applying(transform)
            var line = Path()
            line.move(to: start)
            line.addLine(to: end)
            context.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            context.stroke(line, with: .color(.black.opacity(0.6)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            for (point, fill) in [(start, state.color.color), (end, Color.clear)] {
                let dot = Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
                context.fill(dot, with: .color(fill))
                context.stroke(dot, with: .color(.white), lineWidth: 2)
            }
        }

        if state.tool == .pen, let target = state.penPath, let layer = composition[target.layerID] {
            drawVectorEditing(layer, in: &context, transform: transform)
        }

        if let crop = state.cropRect {
            drawCrop(crop.applying(transform), in: &context)
        }
    }

    /// A vector layer's paths outlined, with their points and the handles of
    /// the point picked out.
    private func drawVectorEditing(_ layer: Layer, in context: inout GraphicsContext, transform: CGAffineTransform) {
        guard let content = layer.vector else { return }
        let toScreen = layer.affineTransform.concatenating(transform)
        for (pathIndex, path) in content.paths.enumerated() {
            context.stroke(Path(path.cgPath).applying(toScreen), with: .color(.accentColor), lineWidth: 1.5)
            for (nodeIndex, node) in path.nodes.enumerated() {
                let isSelected = state.selectedNode == VectorNodeRef(layerID: layer.id, path: pathIndex, node: nodeIndex)
                let anchor = node.point.applying(toScreen)
                if isSelected {
                    for handle in [node.controlIn, node.controlOut].compactMap({ $0 }) {
                        let end = handle.applying(toScreen)
                        var line = Path()
                        line.move(to: anchor)
                        line.addLine(to: end)
                        context.stroke(line, with: .color(.accentColor), lineWidth: 1)
                        let knob = Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10))
                        context.fill(knob, with: .color(.white))
                        context.stroke(knob, with: .color(.accentColor), lineWidth: 1.5)
                    }
                }
                let box = Path(CGRect(x: anchor.x - 5, y: anchor.y - 5, width: 10, height: 10))
                context.fill(box, with: .color(isSelected ? .accentColor : .white))
                context.stroke(box, with: .color(.accentColor), lineWidth: 1.5)
            }
        }
    }

    private func drawCrop(_ rect: CGRect, in context: inout GraphicsContext) {
        var shade = Path(viewport.canvasFrame)
        shade.addRect(rect)
        context.fill(shade, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))

        var thirds = Path()
        for step in 1...2 {
            let x = rect.minX + rect.width * Double(step) / 3
            let y = rect.minY + rect.height * Double(step) / 3
            thirds.move(to: CGPoint(x: x, y: rect.minY))
            thirds.addLine(to: CGPoint(x: x, y: rect.maxY))
            thirds.move(to: CGPoint(x: rect.minX, y: y))
            thirds.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.stroke(thirds, with: .color(.white.opacity(0.5)), lineWidth: 0.5)
        context.stroke(Path(rect), with: .color(.white), lineWidth: 1.5)

        // Corner brackets, which is where the frame is grabbed.
        let arm: CGFloat = min(22, rect.width / 3, rect.height / 3)
        var corners = Path()
        for (x, dx) in [(rect.minX, 1.0), (rect.maxX, -1.0)] {
            for (y, dy) in [(rect.minY, 1.0), (rect.maxY, -1.0)] {
                corners.move(to: CGPoint(x: x + arm * dx, y: y))
                corners.addLine(to: CGPoint(x: x, y: y))
                corners.addLine(to: CGPoint(x: x, y: y + arm * dy))
            }
        }
        context.stroke(corners, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .square))
    }
}
