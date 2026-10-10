import CoreGraphics
import Foundation

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
    /// Whether tilting Apple Pencil shades with its side and turns a
    /// flat nib.
    var usesTilt = true
    var tip: BrushTip = .round
    var dynamics = BrushDynamics()

    static let sizeRange: ClosedRange<Double> = 1...1500

    /// How far the edge feathers out, in canvas pixels.
    var featherRadius: Double { size * softness * 0.5 }
}

/// How a brush's marks vary along a stroke, beyond pressure and tilt.
struct BrushDynamics: Codable, Hashable, Sendable {
    /// How far the stroke thins toward both ends, 0 for not at all.
    var taper = 0.0
    /// How much a quick stroke thins, as a dip pen's line does, 0 for not
    /// at all.
    var speed = 0.0
    /// Whether a stamped tip turns to lie across the way the stroke is
    /// going, as a flat brush does when dragged.
    var followsStroke = false
    /// How far dabs stray from the line, up to a brush's width away.
    var scatter = 0.0
    /// How much each dab's size varies, shrinking at random down to nothing
    /// at 1.
    var sizeJitter = 0.0
    /// How far each dab's colour strays in hue, saturation and brightness.
    var colorJitter = 0.0

    init() {}

    // Each value is read only if it is there, so brushes saved before a
    // value existed still open.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taper = try container.decodeIfPresent(Double.self, forKey: .taper) ?? 0
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 0
        followsStroke = try container.decodeIfPresent(Bool.self, forKey: .followsStroke) ?? false
        scatter = try container.decodeIfPresent(Double.self, forKey: .scatter) ?? 0
        sizeJitter = try container.decodeIfPresent(Double.self, forKey: .sizeJitter) ?? 0
        colorJitter = try container.decodeIfPresent(Double.self, forKey: .colorJitter) ?? 0
    }
}

struct StrokePoint: Equatable, Sendable {
    var location: CGPoint
    /// 0...1; 1 for a finger, which has no pressure to report.
    var pressure: Double = 1
    /// Which way Apple Pencil leans, in radians on the canvas, nil for a
    /// finger.
    var azimuth: Double?
    /// How upright Apple Pencil is, from 0 lying flat to π/2 straight up,
    /// nil for a finger.
    var altitude: Double?
    /// When the point was drawn, in seconds, nil if not known.
    var time: TimeInterval?
}

/// One drag of a brush or eraser, kept as points until it is painted in, so
/// the canvas can show it on top of the layer meanwhile.
struct Stroke: Equatable, Sendable {
    /// What the stroke does where it passes.
    enum Kind: Equatable, Sendable {
        case paint, erase
        /// Retouching: the stroke is a mask the tool's effect shows through.
        case blur, mosaic, heal
        /// The layer's own pixels, from `offset` away, painted through.
        case clone(offset: CGVector)

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
    /// through the stroke is, so the mask is opaque. A clone keeps its
    /// opacity: the copy goes down as see-through as the brush.
    var asMask: Stroke {
        var mask = self
        mask.kind = .paint
        mask.settings.color = .white
        switch kind {
        case .blur, .mosaic, .heal: mask.settings.opacity = 1
        case .paint, .erase, .clone: break
        }
        return mask
    }

    /// Whether the line's width changes along it; a finger's steady 1.0
    /// with nothing else thinning it gets the smooth single-path rendering.
    var usesVaryingWidth: Bool {
        let size = settings.size
        return widths.contains { abs($0 - size) > 0.001 }
    }

    /// The width pressure alone gives a point.
    func width(at point: StrokePoint) -> Double {
        guard settings.usesPressure else { return settings.size }
        // Never thinner than a fifth, so a light touch still marks.
        return settings.size * (0.2 + 0.8 * min(max(point.pressure, 0), 1))
    }

    /// How wide the stroke is at each of its points: pressure's width,
    /// thinned where it was drawn quickly and toward tapered ends.
    var widths: [Double] {
        var result = points.map { width(at: $0) }
        let speed = min(max(settings.dynamics.speed, 0), 1)
        if speed > 0 {
            for (index, pace) in paces.enumerated() {
                // Thins smoothly with pace, to two fifths at a dash.
                result[index] *= 1 - speed * 0.6 * (1 - exp(-pace / 1500))
            }
        }
        let taper = min(max(settings.dynamics.taper, 0), 1)
        guard taper > 0, points.count > 1 else { return result }
        var distances = [0.0]
        for index in 1..<points.count {
            let from = points[index - 1].location, to = points[index].location
            distances.append(distances[index - 1] + hypot(to.x - from.x, to.y - from.y))
        }
        let total = distances[distances.count - 1]
        // At most half the stroke each way, so a short one still meets in
        // the middle at full width.
        let reach = min(taper * settings.size * 8, total / 2)
        guard reach > 0 else { return result }
        for index in result.indices {
            let along = min(distances[index], total - distances[index]) / reach
            guard along < 1 else { continue }
            // Eases out of the point, so the end is fine but not a hair.
            let eased = 1 - (1 - along) * (1 - along)
            result[index] *= 0.08 + 0.92 * eased
        }
        return result
    }

    /// How fast the stroke was moving at each point, in canvas pixels a
    /// second, taken over a few points either side so it does not flicker.
    /// Zero where there are no times.
    var paces: [Double] {
        points.indices.map { index in
            let first = max(index - 3, 0), last = min(index + 3, points.count - 1)
            guard let start = points[first].time, let end = points[last].time, end > start else { return 0 }
            var distance = 0.0
            for step in stride(from: first + 1, through: last, by: 1) {
                let from = points[step - 1].location, to = points[step].location
                distance += hypot(to.x - from.x, to.y - from.y)
            }
            return distance / (end - start)
        }
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
    /// pressure or tapers.
    var segments: [(from: CGPoint, to: CGPoint, width: Double)] {
        let widths = widths
        guard points.count > 1 else {
            return points.indices.map { (points[$0].location, points[$0].location, widths[$0]) }
        }
        return (1..<points.count).map { index in
            (points[index - 1].location, points[index].location, (widths[index - 1] + widths[index]) / 2)
        }
    }

    /// The canvas area the stroke can touch.
    var bounds: CGRect {
        // Chalk scatters its dabs a little past the line, a tilted pencil
        // shades up to two and a half times as wide, and scattered dabs
        // stray up to a width further.
        let stray = usesDabs ? settings.size * (0.85 + scatter * 2.5) : 0
        let reach = settings.size / 2 + settings.featherRadius * 2 + stray + 2
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
            clip.clip(context, canvasSize: canvasSize)
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
        if usesDabs {
            // Stamped tips carry their own soft edge.
            drawDabs(in: context, color: isEraser ? .black : settings.color)
        } else if settings.featherRadius > 0.5 {
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
