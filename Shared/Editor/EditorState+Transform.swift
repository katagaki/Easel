import CoreGraphics
import Foundation

/// The ways the Transform tool bends a layer.
enum TransformMode: String, CaseIterable, Identifiable, Sendable {
    /// Drag the corners: skew and perspective.
    case distort
    /// Drag a grid of points: bend the layer like a sheet.
    case warp

    var id: String { rawValue }
}

/// A layer being bent by the Transform tool, shown on the canvas until it is
/// applied or cancelled.
struct TransformDraft: Equatable {
    var layerID: Layer.ID
    var mode: TransformMode
    /// Where the handles are, in canvas pixels: four corners for distort,
    /// sixteen points for warp.
    var points: [CGPoint]
    /// Where they started, so an untouched draft is not applied.
    var original: [CGPoint]

    var shape: WarpShape { mode == .warp ? .warp(points) : .perspective(points) }
    var isChanged: Bool { points != WarpShape.points(warp: mode == .warp, quad: original) }

    /// The handles that move with the one at `index`: in warp, a corner's
    /// neighbours go with it so its curves keep their shape.
    func handlesMoving(with index: Int) -> [Int] {
        guard mode == .warp else { return [index] }
        let row = index / 4, column = index % 4
        guard (row == 0 || row == 3) && (column == 0 || column == 3) else { return [index] }
        let nextRow = row == 0 ? 1 : 2, nextColumn = column == 0 ? 1 : 2
        return [index, row * 4 + nextColumn, nextRow * 4 + column, nextRow * 4 + nextColumn]
    }
}

/// A transform drag in progress.
struct TransformDrag {
    var start: CGPoint
    /// The handles being moved and where each began.
    var handles: [(index: Int, origin: CGPoint)]
}

extension EditorState {
    /// Starts bending the active layer, its handles on its corners.
    func beginTransformDraft() {
        guard let layer = activeLayer else {
            transformDraft = nil
            return
        }
        if let draft = transformDraft, draft.layerID == layer.id { return }
        let quad = layer.corners
        transformDraft = TransformDraft(
            layerID: layer.id, mode: transformMode,
            points: WarpShape.points(warp: transformMode == .warp, quad: quad), original: quad
        )
        transformPreview = nil
    }

    /// Changes between distort and warp, keeping the shape as near as the
    /// new mode can.
    func setTransformMode(_ mode: TransformMode) {
        transformMode = mode
        guard var draft = transformDraft, draft.mode != mode else { return }
        let shape = draft.shape
        draft.mode = mode
        // A warp grid laid over the perspective, or a warp's corners.
        draft.points = mode == .warp
            ? (0..<16).map { shape.point(Double($0 % 4) / 3, Double($0 / 4) / 3) }
            : shape.corners
        transformDraft = draft
        updateTransformPreview()
    }

    func transformBegan(at point: CGPoint) {
        guard let draft = transformDraft, let layer = activeLayer, !composition.isLocked(layer) else { return }
        // A handle from this far away on screen.
        let reach = 30 / max(viewport.scale, 0.0001)
        let nearest = draft.points.indices.min {
            hypot(draft.points[$0].x - point.x, draft.points[$0].y - point.y)
                < hypot(draft.points[$1].x - point.x, draft.points[$1].y - point.y)
        }
        if let nearest, hypot(draft.points[nearest].x - point.x, draft.points[nearest].y - point.y) <= reach {
            transformDrag = TransformDrag(
                start: point, handles: draft.handlesMoving(with: nearest).map { ($0, draft.points[$0]) }
            )
        } else {
            // Elsewhere, the whole shape moves.
            transformDrag = TransformDrag(start: point, handles: draft.points.enumerated().map { ($0.offset, $0.element) })
        }
    }

    func transformMoved(to point: CGPoint) {
        guard let drag = transformDrag, var draft = transformDraft else { return }
        let dx = point.x - drag.start.x, dy = point.y - drag.start.y
        for handle in drag.handles {
            draft.points[handle.index] = CGPoint(x: handle.origin.x + dx, y: handle.origin.y + dy)
        }
        transformDraft = draft
        updateTransformPreview()
    }

    func transformEnded() {
        transformDrag = nil
    }

    /// Puts the handles back on the layer's corners.
    func resetTransformDraft() {
        guard var draft = transformDraft else { return }
        draft.points = WarpShape.points(warp: draft.mode == .warp, quad: draft.original)
        transformDraft = draft
        transformPreview = nil
    }

    /// The layer as it will look, worked out small and off the main thread;
    /// only the newest is kept.
    func updateTransformPreview() {
        guard let draft = transformDraft, let layer = composition[draft.layerID] else { return }
        let displayed = displayImage(for: layer)
        let mask = layer.activeMask?.image.cgImage
        let size = composition.size
        let scale = min(1, 1200 / max(size.width, size.height))
        transformPreviewTask?.cancel()
        transformPreviewTask = Task { @MainActor in
            let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard !Task.isCancelled else { return nil }
                let source = Bitmap.scaled(Self.masked(displayed, by: mask), toFit: 1200) ?? displayed
                return MeshWarp.render(source, shape: draft.shape, size: size, scale: scale, divisions: 12)
            }.value
            guard !Task.isCancelled, let image, transformDraft == draft else { return }
            transformPreview = LayerPreview(layerID: draft.layerID, image: image)
        }
    }

    /// `image` showing only where `mask` does.
    nonisolated static func masked(_ image: CGImage, by mask: CGImage?) -> CGImage {
        guard let mask else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        return Bitmap.render(size: rect.size) { context in
            Bitmap.draw(mask, in: rect, context: context)
            context.setBlendMode(.sourceIn)
            Bitmap.draw(image, in: rect, context: context)
        }
    }

    /// Bends the layer and its mask for good. The layer comes out lined up
    /// with the canvas; its filters stay.
    func applyTransform() {
        guard let draft = transformDraft, draft.isChanged, let layer = composition[draft.layerID],
              !composition.isLocked(layer) else { return }
        let size = composition.size
        let shape = draft.shape
        enqueue({ () -> TransformedPixels? in
            let image = MeshWarp.render(layer.image.cgImage, shape: shape, size: size)
            let mask = layer.mask.map { MeshWarp.renderMask($0.image.cgImage, shape: shape, size: size) }
            return TransformedPixels(image: image, mask: mask)
        }, apply: { [weak self] result in
            guard let self else { return }
            update { composition in
                guard var current = composition[draft.layerID] else { return }
                current.image = LayerImage(result.image)
                if let mask = result.mask { current.mask?.image = LayerImage(mask) }
                current.text = nil
                current.vector = nil
                current.transform = LayerTransform(position: CGPoint(x: size.width / 2, y: size.height / 2))
                composition[draft.layerID] = current
            }
            transformDraft = nil
            transformPreview = nil
            beginTransformDraft()
        })
    }

    func cancelTransform() {
        transformPreviewTask?.cancel()
        transformDraft = nil
        transformPreview = nil
        beginTransformDraft()
    }
}

/// A layer's pixels and mask after bending, carried back from the work.
struct TransformedPixels: @unchecked Sendable {
    // Unchecked: `CGImage` is immutable once made.
    var image: CGImage
    var mask: CGImage?
}
