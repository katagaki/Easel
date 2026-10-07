import CoreGraphics

/// The part of the canvas edits are confined to, in canvas pixels.
struct Selection: Equatable, Sendable {
    enum Shape: Equatable, Sendable {
        case rectangle(CGRect)
        case ellipse(CGRect)
        /// A freehand outline, closed back to its first point.
        case lasso([CGPoint])
    }

    var shape: Shape
    /// Everything but the shape.
    var isInverted = false

    /// The outline of the shape alone, inversion aside.
    var shapePath: CGPath {
        switch shape {
        case .rectangle(let rect):
            return CGPath(rect: rect.standardized, transform: nil)
        case .ellipse(let rect):
            return CGPath(ellipseIn: rect.standardized, transform: nil)
        case .lasso(let points):
            let path = CGMutablePath()
            guard let first = points.first else { return path }
            path.move(to: first)
            path.addLines(between: points)
            path.closeSubpath()
            return path
        }
    }

    /// The selected area, to be filled or clipped to with the even-odd rule,
    /// which is what lets an inverted selection be a canvas with a hole.
    func path(in canvasSize: CGSize) -> CGPath {
        guard isInverted else { return shapePath }
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: canvasSize))
        path.addPath(shapePath)
        return path
    }

    /// The canvas area the selection reaches.
    func bounds(in canvasSize: CGSize) -> CGRect {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        if isInverted { return canvas }
        return shapePath.boundingBoxOfPath.intersection(canvas)
    }

    /// Whether the selection has any area worth keeping: a tap or a sliver
    /// drawn by accident selects nothing.
    var isMeaningful: Bool {
        let box = shapePath.boundingBoxOfPath
        return box.width >= 2 && box.height >= 2
    }

    /// The selection moved with the canvas when it is cropped or turned.
    func applying(_ transform: CGAffineTransform) -> Selection {
        var copy = self
        switch shape {
        case .rectangle(let rect):
            copy.shape = .lasso(Self.corners(of: rect).map { $0.applying(transform) })
        case .ellipse(let rect):
            // Canvas changes are crops, flips and quarter turns, all of which
            // leave an ellipse described by its bounding box.
            copy.shape = .ellipse(rect.applying(transform).standardized)
        case .lasso(let points):
            copy.shape = .lasso(points.map { $0.applying(transform) })
        }
        return copy
    }

    private static func corners(of rect: CGRect) -> [CGPoint] {
        let rect = rect.standardized
        return [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ]
    }
}
