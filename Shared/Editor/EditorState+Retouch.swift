import CoreGraphics
import Foundation

/// The blurred or tiled copy of a layer the blur and mosaic brushes reveal,
/// worked out when a stroke starts so it can be shown under the finger.
struct RetouchPreparation: @unchecked Sendable {
    // Unchecked: `CGImage` is immutable once made.
    var layerID: Layer.ID
    var kind: Stroke.Kind
    var size: Double
    var strength: Double
    /// The aligned pixels it was made from.
    var source: CGImage
    var image: CGImage

    func matches(_ stroke: Stroke, source: CGImage) -> Bool {
        stroke.kind == kind && stroke.settings.size == size && stroke.settings.opacity == strength
            && source === self.source
    }
}

/// A smear in progress: the layer's pixels being pushed around, and the
/// parts that changed, shown over the layer until the finger lifts.
struct SmudgeSession {
    var layerID: Layer.ID
    var smudger: Smudger
    /// Canvas-aligned pieces of the smeared pixels, oldest first; later ones
    /// are newer and are drawn over earlier ones.
    var patches: [(rect: CGRect, image: CGImage)] = []
}

extension EditorState {
    /// Starts working out the blur or mosaic for the active layer, unless
    /// it is already there for these pixels and settings.
    func prepareRetouchEffect() {
        guard let layer = activeLayer else { return }
        let source = layer.aligned(in: composition.size).image.cgImage
        let kind = strokeKind
        let settings = currentBrush
        if let prepared = retouchEffect, prepared.layerID == layer.id, prepared.kind == kind,
           prepared.size == settings.size, prepared.strength == settings.opacity, prepared.source === source {
            return
        }
        retouchEffect = nil
        Task { @MainActor in
            let image = await Task.detached(priority: .userInitiated) {
                RetouchEffect.image(kind, settings: settings, of: source)
            }.value
            // Only if nothing newer was asked for meanwhile.
            guard activeLayerID == layer.id, strokeKind == kind, currentBrush.size == settings.size,
                  currentBrush.opacity == settings.opacity else { return }
            retouchEffect = RetouchPreparation(
                layerID: layer.id, kind: kind, size: settings.size, strength: settings.opacity,
                source: source, image: image
            )
        }
    }

    // MARK: - Smudge

    func beginSmudge(at point: CGPoint) {
        guard let layer = activeLayer else { return }
        let aligned = layer.aligned(in: composition.size)
        guard let pixels = Bitmap.pixels(of: aligned.image.cgImage) else { return }
        smudge = SmudgeSession(
            layerID: layer.id,
            smudger: Smudger(pixels: pixels, settings: currentBrush, selection: selection, start: point)
        )
    }

    func continueSmudge(to points: [CGPoint]) {
        guard var session = smudge else { return }
        var changed = CGRect.null
        for point in points {
            if let rect = session.smudger.drag(to: point) { changed = changed.union(rect) }
        }
        if !changed.isNull, let image = session.smudger.patch(changed) {
            session.patches.append((changed.integral, image))
        }
        smudge = session
    }

    /// Puts the smeared pixels into the layer. Its filters stay.
    func finishSmudge() {
        guard let session = smudge else { return }
        smudge = nil
        guard !session.patches.isEmpty, let image = session.smudger.pixels.makeImage() else { return }
        let size = composition.size
        update { composition in
            guard var layer = composition[session.layerID] else { return }
            layer.image = LayerImage(image)
            layer.text = nil
            layer.vector = nil
            layer.transform = LayerTransform(position: CGPoint(x: size.width / 2, y: size.height / 2))
            composition[session.layerID] = layer
        }
    }
}
