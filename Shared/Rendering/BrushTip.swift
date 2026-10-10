import CoreGraphics
import Foundation
import SwiftUI

/// The shape a brush lays paint down with.
enum BrushTip: String, Codable, CaseIterable, Identifiable, Sendable {
    /// A smooth round line.
    case round
    /// A grainy line, like graphite on paper.
    case pencil
    /// A flat nib held at an angle: thin one way, broad the other.
    case calligraphy
    /// A soft spray that builds up where it passes again.
    case airbrush
    /// Broken and dry, like chalk or pastel on a rough ground.
    case chalk

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .round: return "Brush.Tip.Round"
        case .pencil: return "Brush.Tip.Pencil"
        case .calligraphy: return "Brush.Tip.Calligraphy"
        case .airbrush: return "Brush.Tip.Airbrush"
        case .chalk: return "Brush.Tip.Chalk"
        }
    }

    var symbolName: String {
        switch self {
        case .round: return "circle.fill"
        case .pencil: return "pencil"
        case .calligraphy: return "pencil.and.scribble"
        case .airbrush: return "aqi.medium"
        case .chalk: return "scribble.variable"
        }
    }

    /// How far apart dabs are, as a share of the brush's width.
    fileprivate var spacing: Double {
        switch self {
        case .round, .pencil: return 0.12
        case .calligraphy: return 0.04
        case .airbrush: return 0.08
        case .chalk: return 0.15
        }
    }

    /// The nib's breadth across, for a flat tip, as a share of its width.
    fileprivate var roundness: Double { self == .calligraphy ? 0.22 : 1 }

    /// How much each dab lays down; low ones build up where they overlap.
    fileprivate var flow: Double {
        switch self {
        case .round, .calligraphy: return 1
        case .pencil: return 0.85
        case .airbrush: return 0.25
        case .chalk: return 0.75
        }
    }

    /// How much of a paper grain the stroke shows, 0 for none: dry tips skip
    /// over the low spots of the paper.
    var grain: Double {
        switch self {
        case .pencil: return 0.4
        case .chalk: return 0.7
        case .round, .calligraphy, .airbrush: return 0
        }
    }

    /// The angle a flat nib is held at when Apple Pencil's tilt is not used.
    static let nibAngle = Double.pi / 4
}

/// One stamp of a brush tip along a stroke.
struct BrushDab: Equatable, Sendable {
    var center: CGPoint
    var diameter: Double
    /// Turned this far, in radians.
    var angle: Double
    /// Height over width; below 1 for a flat nib.
    var roundness: Double
    var opacity: Double
}

extension Stroke {
    /// Whether the stroke is stamped dab by dab rather than drawn as a line:
    /// any tip but round, and round too once its dabs stray or vary.
    var usesDabs: Bool { settings.tip != .round || scatter > 0 || sizeJitter > 0 }

    /// How far dabs stray from the line, as a share of a brush's width.
    var scatter: Double { min(max(settings.dynamics.scatter, 0), 1) }

    var sizeJitter: Double { min(max(settings.dynamics.sizeJitter, 0), 1) }

    /// Where each dab of a stamped stroke goes, the same each time it is
    /// worked out, so the preview and the painted result match.
    var dabs: [BrushDab] {
        let tip = settings.tip
        guard let first = points.first else { return [] }
        var random = SeededRandom(seed: UInt64(points.count == 1 ? 1 : 7))
        let widths = widths
        let follows = settings.dynamics.followsStroke
        let scatter = scatter, sizeJitter = sizeJitter
        func dab(at point: StrokePoint, width: Double, heading: Double) -> BrushDab {
            var diameter = max(1, width)
            if sizeJitter > 0 { diameter = max(1, diameter * (1 - sizeJitter * random.next())) }
            var opacity = tip.flow
            // Laid on its side, a dry tip shades broad and light.
            if tip.grain > 0 {
                let lean = tilt(at: point)
                diameter *= 1 + lean * 1.5
                opacity *= 1 - lean * 0.45
            }
            var center = point.location
            var angle = tip == .calligraphy ? nibAngle(at: point) : random.next() * 2 * .pi
            if follows { angle = heading + .pi / 2 }
            if tip == .chalk {
                center.x += (random.next() - 0.5) * diameter * 0.15
                center.y += (random.next() - 0.5) * diameter * 0.15
            }
            if scatter > 0 {
                // Anywhere in a disc around the line, evenly over its area.
                let toward = random.next() * 2 * .pi, away = sqrt(random.next()) * scatter * width
                center.x += cos(toward) * away
                center.y += sin(toward) * away
            }
            if tip == .round { angle = 0 }
            return BrushDab(
                center: center, diameter: diameter, angle: angle, roundness: tip.roundness, opacity: opacity
            )
        }
        // The first dab faces the way the stroke sets off.
        let start = points.first { $0.location != first.location }?.location ?? first.location
        var result = [dab(
            at: first, width: widths[0],
            heading: atan2(start.y - first.location.y, start.x - first.location.x)
        )]
        // Walks the stroke, dropping a dab every `spacing` of the brush's
        // width at the point reached.
        var carried = 0.0
        for index in 1..<max(points.count, 1) {
            let from = points[index - 1], to = points[index]
            let length = hypot(to.location.x - from.location.x, to.location.y - from.location.y)
            guard length > 0 else { continue }
            func width(at t: Double) -> Double { widths[index - 1] + (widths[index] - widths[index - 1]) * t }
            let heading = atan2(to.location.y - from.location.y, to.location.x - from.location.x)
            var travelled = 0.0
            while true {
                let step = max(0.5, width(at: travelled / length) * tip.spacing)
                let needed = step - carried
                guard travelled + needed <= length else {
                    carried += length - travelled
                    break
                }
                travelled += needed
                carried = 0
                let at = travelled / length
                result.append(dab(at: StrokePoint(
                    location: CGPoint(
                        x: from.location.x + (to.location.x - from.location.x) * at,
                        y: from.location.y + (to.location.y - from.location.y) * at
                    ),
                    pressure: from.pressure + (to.pressure - from.pressure) * at,
                    azimuth: to.azimuth, altitude: to.altitude
                ), width: width(at: at), heading: heading))
            }
        }
        return result
    }

    /// The angle a flat nib lies at for this point: across the way Apple
    /// Pencil leans, as a chisel tip's edge is, or the usual slant.
    private func nibAngle(at point: StrokePoint) -> Double {
        guard settings.usesTilt, let azimuth = point.azimuth else { return BrushTip.nibAngle }
        return azimuth + .pi / 2
    }

    /// How far Apple Pencil is laid over, 0 when held upright to past 60°,
    /// up to 1 lying flat.
    private func tilt(at point: StrokePoint) -> Double {
        guard settings.usesTilt, let altitude = point.altitude else { return 0 }
        let upright = Double.pi / 3
        return min(max((upright - altitude) / upright, 0), 1)
    }

    /// How large the paper's grain is on the canvas, for this brush: finer
    /// for small brushes, coarser for big ones, so it reads at any size.
    var grainScale: Double { max(1, settings.size / 20) }

    /// Stamps the dabs in solid `color` into `context`, then lets the paper
    /// show through as the tip's grain asks.
    func drawDabs(in context: CGContext, color: RGBAColor) {
        defer {
            if let grain = PaperGrain.image(strength: settings.tip.grain) {
                context.saveGState()
                context.clip(to: bounds)
                context.setBlendMode(.destinationIn)
                context.setAlpha(1)
                let side = Double(grain.width) * grainScale
                context.draw(grain, in: CGRect(x: 0, y: 0, width: side, height: side), byTiling: true)
                context.restoreGState()
            }
        }
        let tip = BrushTipImage.tinted(settings.tip, softness: settings.softness, color: color)
        for dab in dabs {
            context.saveGState()
            context.translateBy(x: dab.center.x, y: dab.center.y)
            context.rotate(by: dab.angle)
            context.scaleBy(x: 1, y: dab.roundness)
            context.setAlpha(dab.opacity)
            let radius = dab.diameter / 2
            Bitmap.draw(tip, in: CGRect(x: -radius, y: -radius, width: dab.diameter, height: dab.diameter), context: context)
            context.restoreGState()
        }
    }
}

/// The images brush tips are stamped with, white on clear, made once for
/// each tip and softness.
enum BrushTipImage {
    private static let size = 128
    private static let cache = TipCache()

    /// The tip's image in `color`.
    static func tinted(_ tip: BrushTip, softness: Double, color: RGBAColor) -> CGImage {
        let shape = image(tip, softness: softness)
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        return Bitmap.render(size: rect.size) { context in
            Bitmap.draw(shape, in: rect, context: context)
            context.setBlendMode(.sourceIn)
            context.setFillColor(color.withAlpha(1).cgColor)
            context.fill(rect)
        }
    }

    static func image(_ tip: BrushTip, softness: Double) -> CGImage {
        // Softness in twentieths is fine enough to see no steps.
        let step = Int((min(max(softness, 0), 1) * 20).rounded())
        let key = "\(tip.rawValue)-\(step)"
        if let cached = cache.image(for: key) { return cached }
        let made = make(tip, softness: Double(step) / 20)
        cache.store(made, for: key)
        return made
    }

    private static func make(_ tip: BrushTip, softness: Double) -> CGImage {
        var random = SeededRandom(seed: 42)
        // Grain in cells two pixels across, for the dry tips.
        let cells = size / 2
        let grain = (0..<(cells * cells)).map { _ in random.next() }
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        let center = Double(size) / 2
        for y in 0..<size {
            for x in 0..<size {
                let dx = (Double(x) + 0.5 - center) / center
                let dy = (Double(y) + 0.5 - center) / center
                let reach = sqrt(dx * dx + dy * dy)
                guard reach < 1 else { continue }
                var alpha: Double
                if tip == .airbrush {
                    alpha = 1 - reach * reach
                } else {
                    // Solid to the softness's edge, fading to nothing at the rim.
                    let core = 1 - max(softness, 0.04)
                    alpha = reach <= core ? 1 : max(0, (1 - reach) / (1 - core))
                }
                // Chalk's edge is ragged; the paper gives the rest its grain.
                if tip == .chalk, reach > 0.7 {
                    alpha *= grain[(y / 2) * cells + x / 2] > 0.4 ? 1 : 0.1
                }
                let value = UInt8(min(max(alpha, 0), 1) * 255)
                let index = (y * size + x) * 4
                bytes[index] = value
                bytes[index + 1] = value
                bytes[index + 2] = value
                bytes[index + 3] = value
            }
        }
        return PixelBuffer(width: size, height: size, bytes: bytes).makeImage() ?? Bitmap.empty
    }
}

/// A tile of paper texture, white with the paper's tooth in its alpha:
/// opaque on the high spots, see-through in the hollows a dry tip skips.
enum PaperGrain {
    private static let size = 128
    private static let cache = TipCache()

    static func image(strength: Double) -> CGImage? {
        guard strength > 0 else { return nil }
        let key = "grain-\(Int((strength * 100).rounded()))"
        if let cached = cache.image(for: key) { return cached }
        var random = SeededRandom(seed: 9)
        // Noise smoothed a little, so the tooth has some body.
        var values = (0..<(size * size)).map { _ in Float(random.next()) }
        Healer.boxBlur(&values, width: size, height: size, radius: 1, passes: 1)
        let low = values.min() ?? 0, high = values.max() ?? 1
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for index in 0..<(size * size) {
            let height = (values[index] - low) / max(high - low, 0.0001)
            // Stronger grain cuts deeper into the hollows.
            let tooth = min(max((Double(height) - strength * 0.5) / max(1 - strength * 0.5, 0.0001), 0), 1)
            let alpha = 1 - strength + strength * tooth
            let value = UInt8(min(max(alpha, 0), 1) * 255)
            for channel in 0..<4 { bytes[index * 4 + channel] = value }
        }
        let made = PixelBuffer(width: size, height: size, bytes: bytes).makeImage() ?? Bitmap.empty
        cache.store(made, for: key)
        return made
    }
}

/// Tip images made so far, shared by every thread that paints.
private final class TipCache: @unchecked Sendable {
    // Unchecked: every access goes through the lock.
    private let lock = NSLock()
    private var images: [String: CGImage] = [:]

    func image(for key: String) -> CGImage? {
        lock.withLock { images[key] }
    }

    func store(_ image: CGImage, for key: String) {
        lock.withLock { images[key] = image }
    }
}

/// Numbers that look random but come out the same every time from the same
/// seed, so a stroke's grain and scatter never flicker.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    /// The next number, 0..<1.
    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}
