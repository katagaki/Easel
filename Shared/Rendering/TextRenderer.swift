import UIKit

/// Sets a text layer's words into pixels.
enum TextRenderer {
    static func font(for text: TextContent) -> UIFont {
        let size = max(1, text.fontSize)
        var descriptor = UIFont.systemFont(ofSize: size, weight: text.isBold ? .bold : .regular).fontDescriptor
        let design: UIFontDescriptor.SystemDesign = switch text.design {
        case .standard: .default
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
        descriptor = descriptor.withDesign(design) ?? descriptor
        if text.isItalic {
            descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) ?? descriptor
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func attributedString(for text: TextContent) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = switch text.alignment {
        case .leading: .natural
        case .center: .center
        case .trailing: .right
        }
        let color = UIColor(
            red: text.color.red, green: text.color.green, blue: text.color.blue, alpha: text.color.alpha
        )
        // An empty layer still needs a line's height to be found and tapped.
        let string = text.string.isEmpty ? " " : text.string
        return NSAttributedString(string: string, attributes: [
            .font: font(for: text), .foregroundColor: color, .paragraphStyle: paragraph,
        ])
    }

    /// The text drawn on a transparent image just large enough to hold it,
    /// with a little room so italics and descenders are not clipped.
    static func render(_ text: TextContent) -> CGImage {
        let string = attributedString(for: text)
        let bounds = string.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
        )
        let padding = ceil(text.fontSize * 0.15)
        let size = CGSize(
            width: min(ceil(bounds.width) + padding * 2, CGFloat(Bitmap.maximumDimension)),
            height: min(ceil(bounds.height) + padding * 2, CGFloat(Bitmap.maximumDimension))
        )
        return Bitmap.render(size: size) { context in
            UIGraphicsPushContext(context)
            string.draw(
                with: CGRect(x: padding, y: padding, width: size.width - padding * 2, height: size.height - padding * 2),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
            )
            UIGraphicsPopContext()
        }
    }
}
