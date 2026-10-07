import SwiftUI

/// What a finger or pencil does on the canvas.
enum Tool: String, CaseIterable, Identifiable, Sendable {
    case move, select, crop
    case brush, eraser, fill, gradient, eyedropper
    case smudge, blur, mosaic, heal
    case text, shape

    var id: String { rawValue }

    /// The tools as the carousel and rail group them: arranging, painting,
    /// retouching, adding.
    static let groups: [[Tool]] = [
        [.move, .select, .crop],
        [.brush, .eraser, .fill, .gradient, .eyedropper],
        [.smudge, .blur, .mosaic, .heal],
        [.text, .shape],
    ]

    var symbolName: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .select: return "rectangle.dashed"
        case .crop: return "crop"
        case .brush: return "paintbrush.pointed"
        case .eraser: return "eraser"
        case .fill: return "drop"
        case .gradient: return "circle.lefthalf.striped.horizontal"
        case .eyedropper: return "eyedropper"
        case .smudge: return "hand.point.up.left"
        case .blur: return "aqi.medium"
        case .mosaic: return "square.grid.3x3.fill"
        case .heal: return "bandage"
        case .text: return "textformat"
        case .shape: return "square.on.circle"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .move: return "Tool.Move"
        case .select: return "Tool.Select"
        case .crop: return "Tool.Crop"
        case .brush: return "Tool.Brush"
        case .eraser: return "Tool.Eraser"
        case .fill: return "Tool.Fill"
        case .gradient: return "Tool.Gradient"
        case .eyedropper: return "Tool.Eyedropper"
        case .smudge: return "Tool.Smudge"
        case .blur: return "Tool.Blur"
        case .mosaic: return "Tool.Mosaic"
        case .heal: return "Tool.Heal"
        case .text: return "Tool.Text"
        case .shape: return "Tool.Shape"
        }
    }

    /// The single key that picks the tool from a hardware keyboard, the same
    /// letters desktop editors use.
    var shortcut: KeyEquivalent {
        switch self {
        case .move: return "v"
        case .select: return "m"
        case .crop: return "c"
        case .brush: return "b"
        case .eraser: return "e"
        case .fill: return "g"
        case .gradient: return "d"
        case .eyedropper: return "i"
        case .smudge: return "s"
        case .blur: return "r"
        case .mosaic: return "o"
        case .heal: return "j"
        case .text: return "t"
        case .shape: return "u"
        }
    }

    /// Tools that change the active layer's pixels, and so need it to be
    /// visible and unlocked.
    var paintsPixels: Bool {
        switch self {
        case .brush, .eraser, .fill, .gradient, .smudge, .blur, .mosaic, .heal: return true
        default: return false
        }
    }

    /// Brushes that change what is already there rather than adding colour.
    var isRetouch: Bool {
        switch self {
        case .smudge, .blur, .mosaic, .heal: return true
        default: return false
        }
    }

    /// Tools that are dragged like a brush and leave a stroke.
    var usesStrokes: Bool {
        switch self {
        case .brush, .eraser, .blur, .mosaic, .heal: return true
        default: return false
        }
    }
}

/// The ways the selection tool draws.
enum SelectionKind: String, CaseIterable, Identifiable, Sendable {
    case rectangle, ellipse, lasso
    /// A freehand outline that clings to the edges it is drawn along.
    case magnetic
    /// A tap picks out the run of similar colour around it.
    case magic
    /// A tap picks out the object under it, found by Vision.
    case object

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .rectangle: return "rectangle.dashed"
        case .ellipse: return "circle.dashed"
        case .lasso: return "lasso"
        case .magnetic: return "lasso.badge.sparkles"
        case .magic: return "wand.and.rays"
        case .object: return "person.crop.rectangle.badge.plus"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .rectangle: return "Select.Rectangle"
        case .ellipse: return "Select.Ellipse"
        case .lasso: return "Select.Lasso"
        case .magnetic: return "Select.Magnetic"
        case .magic: return "Select.Magic"
        case .object: return "Select.Object"
        }
    }

    /// Selections dragged out by hand, as opposed to picked with a tap.
    var isDrawn: Bool { self != .magic && self != .object }
}

/// Fixed proportions the crop tool can hold to.
enum CropAspect: String, CaseIterable, Identifiable, Sendable {
    case free, original, square, fourThree, threeTwo, sixteenNine

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .free: return "Crop.Aspect.Free"
        case .original: return "Crop.Aspect.Original"
        case .square: return "Crop.Aspect.Square"
        case .fourThree: return "Crop.Aspect.FourThree"
        case .threeTwo: return "Crop.Aspect.ThreeTwo"
        case .sixteenNine: return "Crop.Aspect.SixteenNine"
        }
    }

    /// Width over height, nil when any shape goes. Landscape or portrait
    /// follows the canvas.
    func ratio(for canvasSize: CGSize) -> Double? {
        let landscape = canvasSize.width >= canvasSize.height
        let base: Double
        switch self {
        case .free: return nil
        case .original: return canvasSize.width / canvasSize.height
        case .square: return 1
        case .fourThree: base = 4.0 / 3
        case .threeTwo: base = 3.0 / 2
        case .sixteenNine: base = 16.0 / 9
        }
        return landscape ? base : 1 / base
    }
}

/// A panel presented over the canvas: a sheet on iPhone, the inspector on iPad.
enum EditorPanel: String, Identifiable, Hashable, Sendable {
    case layers
    case adjustments
    /// The active layer's own filters, which stay editable.
    case filters
    /// One-tap looks painted into the active layer.
    case looks
    case text
    case imageSize

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .layers: return "Panel.Layers.Title"
        case .adjustments: return "Panel.Adjustments.Title"
        case .filters: return "Panel.Filters.Title"
        case .looks: return "Panel.Looks.Title"
        case .text: return "Panel.Text.Title"
        case .imageSize: return "Panel.ImageSize.Title"
        }
    }

    var symbolName: String {
        switch self {
        case .layers: return "square.3.layers.3d"
        case .adjustments: return "slider.horizontal.3"
        case .filters: return "camera.filters"
        case .looks: return "wand.and.sparkles"
        case .text: return "textformat"
        case .imageSize: return "arrow.up.left.and.arrow.down.right"
        }
    }

    /// Panels that change the picture while open keep it in view: on iPhone
    /// they stop at half height and the canvas moves into the top half.
    var keepsCanvasVisible: Bool {
        switch self {
        case .layers, .adjustments, .filters, .looks, .text: return true
        case .imageSize: return false
        }
    }
}
