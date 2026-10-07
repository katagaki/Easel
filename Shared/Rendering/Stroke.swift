import CoreGraphics

/// How a brush or eraser lays down paint.
struct BrushSettings: Codable, Equatable, Sendable {
    /// Diameter, in canvas pixels.
    var size: Double
    var opacity: Double = 1
    /// From a hard edge at 0 to a fully feathered one at 1.
    var softness: Double = 0
    var color: RGBAColor = .black
    /// Whether Apple Pencil pressure thins the line.
    var usesPressure = true

    static let sizeRange: ClosedRange<Double> = 1...1500

    /// How far the edge feathers out, in canvas pixels.
    var featherRadius: Double { size * softness * 0.5 }
}

struct StrokePoint: Equatable, Sendable {
    var location: CGPoint
    /// 0...1; 1 for a finger, which has no pressure to report.
    var pressure: Double = 1
}

/// One drag of a brush or eraser, kept as points until it is painted in, so
/// the canvas can show it on top of the layer meanwhile.
struct Stroke: Equatable, Sendable {
    /// What the stroke does where it passes.
    enum Kind: Equatable, Sendable {
        case paint, erase
        /// Retouching: the stroke is a mask the tool's effect shows through.
        case blur, mosaic, heal

        /// Whether the stroke lays down the brush's colour or takes away;
        /// the rest are masks.
        var isPaint: Bool { self == .paint || self == .erase }
    }

    var points: [StrokePoint]
    var settings: BrushSettings
    var kind: Kind
    /// The selection it is confined to.
    var clip: Selection?

    init(points: [StrokePoint], settings: BrushSettings, kind: Kind, clip: Selection? = nil) {
        self.points = points
        self.settings = settings
        self.kind = kind
        self.clip = clip
    }

    init(points: [StrokePoint], settings: BrushSettings, isEraser: Bool, clip: Selection? = nil) {
        self.init(points: points, settings: settings, kind: isEraser ? .erase : .paint, clip: clip)
    }

    var isEraser: Bool { kind == .erase }

    /// The same stroke, laying down solid white: the shape of a mask. For
    /// the retouching brushes, strength is how much they do, not how see-
    /// through the stroke is, so the mask is opaque.
    var asMask: Stroke {
        var mask = self
        mask.kind = .paint
        mask.settings.color = .white
        if !kind.isPaint { mask.settings.opacity = 1 }
        return mask
    }

    /// Pressure is ignored below this much variation, so a finger's steady
    /// 1.0 gets the smooth single-path rendering.
    private var usesVaryingWidth: Bool {
        guard settings.usesPressure else { return false }
        return points.contains { $0.pressure < 0.999 }
    }

    func width(at point: StrokePoint) -> Double {
        guard settings.usesPressure else { return settings.size }
        // Never thinner than a fifth, so a light touch still marks.
        return settings.size * (0.2 + 0.8 * min(max(point.pressure, 0), 1))
    }

    /// The stroke as a single centre line through the midpoints of its
    /// samples, which rounds off the corners between them.
    var smoothedPath: CGPath {
        let path = CGMutablePath()
        guard let first = points.first?.location else { return path }
        path.move(to: first)
        guard points.count > 1 else {
            path.addLine(to: first)
            return path
        }
        for index in 1..<points.count {
            let previous = points[index - 1].location
            let current = points[index].location
            let middle = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            if index == 1 {
                path.addLine(to: middle)
            } else {
                path.addQuadCurve(to: middle, control: previous)
            }
        }
        path.addLine(to: points[points.count - 1].location)
        return path
    }

    /// Short pieces, each with its own width, for strokes whose width follows
    /// pressure.
    var segments: [(from: CGPoint, to: CGPoint, width: Double)] {
        guard points.count > 1 else {
            return points.map { ($0.location, $0.location, width(at: $0)) }
        }
        return (1..<points.count).map { index in
            let from = points[index - 1]
            let to = points[index]
            return (from.location, to.location, (width(at: from) + width(at: to)) / 2)
        }
    }

    /// The canvas area the stroke can touch.
    var bounds: CGRect {
        let reach = settings.size / 2 + settings.featherRadius * 2 + 2
        return smoothedPath.boundingBoxOfPath.insetBy(dx: -reach, dy: -reach)
    }

    /// Lays the stroke's shape down in solid `color`, untouched by opacity
    /// or feathering; callers wrap it in those.
    func drawShape(in context: CGContext, color: CGColor) {
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(color)
        if usesVaryingWidth {
            for segment in segments {
                context.setLineWidth(segment.width)
                context.move(to: segment.from)
                context.addLine(to: segment.to)
                context.strokePath()
            }
        } else {
            context.setLineWidth(settings.size)
            context.addPath(smoothedPath)
            context.strokePath()
        }
    }

    /// Paints the stroke into `context`, which already holds the layer's
    /// pixels in canvas coordinates.
    func paint(in context: CGContext, canvasSize: CGSize) {
        context.saveGState()
        if let clip {
            context.addPath(clip.path(in: canvasSize))
            context.clip(using: .evenOdd)
        }
        context.setAlpha(settings.opacity)
        context.setBlendMode(isEraser ? .destinationOut : .normal)
        // One transparency layer for the whole stroke, so where its pieces
        // overlap they do not build up past the brush's opacity.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        // The opacity and blend mode above are for putting the finished
        // stroke down; inside it, everything is drawn solid.
        context.setAlpha(1)
        context.setBlendMode(.normal)
        let color = isEraser ? RGBAColor.black.cgColor : settings.color.withAlpha(1).cgColor
        if settings.featherRadius > 0.5 {
            // A shadow is CoreGraphics' only blur. The shape is drawn a canvas
            // away and only its blurred shadow is cast back into place. The
            // offset is horizontal: shadows ignore the flipped y axis.
            let away = canvasSize.width + bounds.width + settings.featherRadius * 4
            context.setShadow(offset: CGSize(width: away, height: 0), blur: settings.featherRadius * 2, color: color)
            context.translateBy(x: -away, y: 0)
            drawShape(in: context, color: color)
        } else {
            drawShape(in: context, color: color)
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }
}
