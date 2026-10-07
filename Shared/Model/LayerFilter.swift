import CoreGraphics
import Foundation

/// A filter kept on a layer rather than painted into it. A layer's filters
/// run in order over its own pixels every time it is drawn, so any of them
/// can be changed, turned off, moved or taken away later.
struct LayerFilter: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case blackAndWhite, sepia, saturation, brightness, contrast
        case gaussianBlur, motionBlur, zoomBlur, mosaic

        var id: String { rawValue }

        /// Tone and colour first, then the blurs and the mosaic, which is how
        /// the add menu groups them.
        static let groups: [[Kind]] = [
            [.blackAndWhite, .sepia, .saturation, .brightness, .contrast],
            [.gaussianBlur, .motionBlur, .zoomBlur, .mosaic],
        ]

        var label: String {
            switch self {
            case .blackAndWhite: return String(localized: "LayerFilter.BlackAndWhite")
            case .sepia: return String(localized: "LayerFilter.Sepia")
            case .saturation: return String(localized: "LayerFilter.Saturation")
            case .brightness: return String(localized: "LayerFilter.Brightness")
            case .contrast: return String(localized: "LayerFilter.Contrast")
            case .gaussianBlur: return String(localized: "LayerFilter.GaussianBlur")
            case .motionBlur: return String(localized: "LayerFilter.MotionBlur")
            case .zoomBlur: return String(localized: "LayerFilter.ZoomBlur")
            case .mosaic: return String(localized: "LayerFilter.Mosaic")
            }
        }

        var symbolName: String {
            switch self {
            case .blackAndWhite: return "circle.righthalf.filled"
            case .sepia: return "sun.dust"
            case .saturation: return "drop.halffull"
            case .brightness: return "sun.max"
            case .contrast: return "circle.lefthalf.filled"
            case .gaussianBlur: return "aqi.medium"
            case .motionBlur: return "wind"
            case .zoomBlur: return "scope"
            case .mosaic: return "square.grid.3x3.fill"
            }
        }

        /// Filters that push either way from no change have zero in the
        /// middle; the rest run from nothing to full strength.
        var amountRange: ClosedRange<Double> {
            switch self {
            case .saturation, .brightness, .contrast: return -1...1
            default: return 0...1
            }
        }

        /// Where a new filter starts: enough to see it working.
        var defaultAmount: Double {
            switch self {
            case .blackAndWhite, .sepia: return 1
            case .saturation: return 0.5
            case .brightness: return 0.2
            case .contrast: return 0.3
            case .gaussianBlur, .motionBlur, .zoomBlur, .mosaic: return 0.3
            }
        }

        var hasAngle: Bool { self == .motionBlur }
        var hasCenter: Bool { self == .zoomBlur }
    }

    var id = UUID()
    var kind: Kind
    var isEnabled = true
    /// Strength, within `kind.amountRange`.
    var amount: Double
    /// Motion blur's direction, in degrees.
    var angle: Double = 0
    /// Zoom blur's centre, as a fraction of the layer's width and height
    /// from its top left.
    var centerX: Double = 0.5
    var centerY: Double = 0.5

    init(kind: Kind) {
        self.kind = kind
        amount = kind.defaultAmount
    }
}

extension Layer {
    /// The filters that are switched on, in the order they run.
    var activeFilters: [LayerFilter] { filters.filter(\.isEnabled) }

    var hasActiveFilters: Bool { filters.contains { $0.isEnabled } }

    /// The layer's pixels as they show: filters and mask applied, at full size.
    var renderedImage: CGImage {
        guard hasActiveFilters || activeMask != nil else { return image.cgImage }
        return FilterCache.shared.image(
            for: FilterCache.Key(layer: self, maxPixelSize: nil, includesMask: true), source: image, mask: activeMask
        )
    }
}
