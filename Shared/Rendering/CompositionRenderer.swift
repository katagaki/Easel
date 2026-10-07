import CoreGraphics

/// Flattens layers into one image, the way the canvas shows them.
enum CompositionRenderer {
    static func render(_ composition: Composition, background: RGBAColor? = nil) -> CGImage {
        render(layers: composition.layers, size: composition.size, background: background)
    }

    static func render(layers: [Layer], size: CGSize, background: RGBAColor? = nil) -> CGImage {
        Bitmap.render(size: size) { context in
            if let background {
                context.setFillColor(background.cgColor)
                context.fill(CGRect(origin: .zero, size: size))
            }
            draw(layers, in: context)
        }
    }

    /// Draws the layers into a context already set up in canvas coordinates.
    static func draw(_ layers: [Layer], in context: CGContext) {
        for layer in layers where layer.isVisible && layer.opacity > 0 {
            context.saveGState()
            context.setAlpha(layer.opacity)
            context.setBlendMode(layer.blendMode.cgBlendMode)
            context.concatenate(layer.affineTransform)
            Bitmap.draw(layer.renderedImage, in: CGRect(origin: .zero, size: layer.image.size), context: context)
            context.restoreGState()
        }
    }

    /// A smaller copy of the whole picture, for previews and thumbnails.
    static func thumbnail(_ composition: Composition, maxPixelSize: Int, background: RGBAColor? = nil) -> CGImage {
        let longest = max(composition.size.width, composition.size.height)
        let factor = min(1, Double(maxPixelSize) / longest)
        let size = CGSize(
            width: max(1, (composition.size.width * factor).rounded()),
            height: max(1, (composition.size.height * factor).rounded())
        )
        return Bitmap.render(size: size) { context in
            if let background {
                context.setFillColor(background.cgColor)
                context.fill(CGRect(origin: .zero, size: size))
            }
            context.scaleBy(x: size.width / composition.size.width, y: size.height / composition.size.height)
            draw(composition.layers, in: context)
        }
    }

    /// The colour the picture shows at a canvas point, found by drawing the
    /// whole stack into a single pixel.
    static func color(at point: CGPoint, in composition: Composition) -> RGBAColor? {
        guard composition.canvasRect.contains(point) else { return nil }
        let image = Bitmap.render(size: CGSize(width: 1, height: 1)) { context in
            context.translateBy(x: -point.x.rounded(.down), y: -point.y.rounded(.down))
            draw(composition.layers, in: context)
        }
        guard let pixels = Bitmap.pixels(of: image) else { return nil }
        let sample = pixels.color(x: 0, y: 0)
        guard sample.alpha > 0 else { return nil }
        // The bytes are Display P3; colours are kept in extended sRGB.
        let p3 = CGColor(
            colorSpace: Bitmap.colorSpace,
            components: [sample.red / 255, sample.green / 255, sample.blue / 255, sample.alpha / 255]
        )
        return p3.flatMap(RGBAColor.init)
    }
}
