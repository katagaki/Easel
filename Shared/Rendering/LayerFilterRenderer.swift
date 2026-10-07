import CoreImage
import CoreImage.CIFilterBuiltins
import Synchronization

extension LayerFilter {
    /// The filter as one step of a Core Image chain. Sizes are fractions of
    /// the image, so a filter looks the same on a small copy as at full size.
    func apply(to input: CIImage) -> CIImage {
        let extent = input.extent
        let unit = max(extent.width, extent.height) / 1000
        let output: CIImage
        switch kind {
        case .blackAndWhite:
            let filter = CIFilter.colorControls()
            filter.inputImage = input
            filter.saturation = Float(1 - min(max(amount, 0), 1))
            output = filter.outputImage ?? input
        case .sepia:
            let filter = CIFilter.sepiaTone()
            filter.inputImage = input
            filter.intensity = Float(amount)
            output = filter.outputImage ?? input
        case .saturation:
            let filter = CIFilter.colorControls()
            filter.inputImage = input
            filter.saturation = Float(1 + amount)
            output = filter.outputImage ?? input
        case .brightness:
            let filter = CIFilter.colorControls()
            filter.inputImage = input
            filter.brightness = Float(amount * 0.5)
            output = filter.outputImage ?? input
        case .contrast:
            let filter = CIFilter.colorControls()
            filter.inputImage = input
            filter.contrast = Float(1 + amount * (amount > 0 ? 1 : 0.75))
            output = filter.outputImage ?? input
        case .gaussianBlur:
            // Clamped first so the edges blur into themselves rather than
            // into transparency.
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = input.clampedToExtent()
            filter.radius = Float(amount * 50 * unit)
            output = filter.outputImage ?? input
        case .motionBlur:
            let filter = CIFilter.motionBlur()
            filter.inputImage = input.clampedToExtent()
            filter.radius = Float(amount * 80 * unit)
            // Core Image turns anticlockwise with y up; on screen, with y
            // down, the same number turns clockwise, which is what the
            // slider says.
            filter.angle = Float(-angle * .pi / 180)
            output = filter.outputImage ?? input
        case .zoomBlur:
            let filter = CIFilter.zoomBlur()
            filter.inputImage = input.clampedToExtent()
            filter.amount = Float(amount * 10 * unit)
            filter.center = CGPoint(
                x: extent.minX + centerX * extent.width, y: extent.minY + (1 - centerY) * extent.height
            )
            output = filter.outputImage ?? input
        case .mosaic:
            let filter = CIFilter.pixellate()
            filter.inputImage = input.clampedToExtent()
            filter.scale = Float(max(1, amount * 60 * unit))
            filter.center = CGPoint(x: extent.minX, y: extent.maxY)
            output = filter.outputImage ?? input
        }
        return output.cropped(to: extent)
    }

    /// A chain of filters, run in order.
    static func apply(_ filters: [LayerFilter], to input: CIImage) -> CIImage {
        filters.reduce(input) { image, filter in filter.apply(to: image) }
    }
}

/// Filtered layers, worked out once and kept a while, so a layer whose
/// filters did not change is not filtered again for every frame, save or
/// colour sample.
final class FilterCache: Sendable {
    static let shared = FilterCache()

    struct Key: Hashable, Sendable {
        var imageID: UUID
        var filters: [LayerFilter]
        /// Nil for full size; otherwise the longest side of a smaller copy.
        var maxPixelSize: Int?
        /// The mask's pixels, when the result is masked. The canvas masks
        /// layers itself, so what it shows leaves this out.
        var maskID: UUID?

        init(layer: Layer, maxPixelSize: Int?, includesMask: Bool = false) {
            imageID = layer.image.id
            filters = layer.activeFilters
            self.maxPixelSize = maxPixelSize
            maskID = includesMask ? layer.activeMask?.image.id : nil
        }
    }

    /// Few, because a full-size layer is tens of megabytes.
    private static let capacity = 6
    private let entries = Mutex<[(key: Key, image: CGImage)]>([])

    func cached(_ key: Key) -> CGImage? {
        entries.withLock { entries in
            guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
            // Most recently used last.
            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.image
        }
    }

    func image(for key: Key, source: LayerImage, mask: LayerMask? = nil) -> CGImage {
        if let cached = cached(key) { return cached }
        let input = key.maxPixelSize.map { source.preview(maxPixelSize: $0) } ?? source.cgImage
        let applyMask = key.maskID != nil ? mask : nil
        let image = ImageProcessing.apply({ image in
            let filtered = LayerFilter.apply(key.filters, to: image)
            return applyMask?.apply(to: filtered) ?? filtered
        }, to: input)
        entries.withLock { entries in
            entries.append((key, image))
            if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
        }
        return image
    }
}
