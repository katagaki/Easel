import CoreGraphics
import SwiftUI

/// A colour as it is kept in a document: gamma-encoded extended sRGB
/// components, which is what SwiftUI resolves colours to, so a colour picked
/// from the system picker survives the round trip — wide-gamut picks included.
struct RGBAColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    static let black = RGBAColor(red: 0, green: 0, blue: 0)
    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let clear = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        self.init(
            red: Double(resolved.red), green: Double(resolved.green),
            blue: Double(resolved.blue), alpha: Double(resolved.opacity)
        )
    }

    /// Reads a colour CoreGraphics produced, in whatever space it is in.
    init?(_ cgColor: CGColor) {
        guard let space = CGColorSpace(name: CGColorSpace.extendedSRGB),
              let converted = cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 4 else { return nil }
        self.init(red: components[0], green: components[1], blue: components[2], alpha: components[3])
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var cgColor: CGColor {
        let space = CGColorSpace(name: CGColorSpace.extendedSRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGColor(colorSpace: space, components: [red, green, blue, alpha])
            ?? CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    func withAlpha(_ alpha: Double) -> RGBAColor {
        var copy = self
        copy.alpha = alpha
        return copy
    }

    /// `#RRGGBB`, for showing beside a swatch.
    var hexString: String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
