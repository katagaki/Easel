import CoreGraphics
import Foundation
import Testing
@testable import Easel

@Suite("Layer filters")
struct LayerFilterTests {
    private let size = CGSize(width: 8, height: 4)

    private func layer(_ filters: [LayerFilter]) -> Layer {
        var layer = Layer(name: "Halves", image: LayerImage(TestImages.halves()), canvasSize: size)
        layer.filters = filters
        return layer
    }

    private func isGrey(_ image: CGImage, x: Int, y: Int) -> Bool {
        let pixel = TestImages.pixel(image, x: x, y: y)
        return abs(pixel.red - pixel.green) < 12 && abs(pixel.green - pixel.blue) < 12
    }

    @Test func filtersChangeTheLookButNotThePixels() {
        let filtered = layer([LayerFilter(kind: .blackAndWhite)])
        #expect(isGrey(filtered.renderedImage, x: 1, y: 1))
        #expect(TestImages.isRed(filtered.image.cgImage, x: 1, y: 1))
        #expect(isGrey(CompositionRenderer.render(Composition(size: size, layers: [filtered])), x: 1, y: 1))
    }

    @Test func turningAFilterOffRestoresTheLayer() {
        var filter = LayerFilter(kind: .blackAndWhite)
        filter.isEnabled = false
        let off = layer([filter])
        #expect(!off.hasActiveFilters)
        #expect(off.renderedImage === off.image.cgImage)
    }

    @Test func filtersRunInOrder() {
        let mono = LayerFilter(kind: .blackAndWhite)
        let sepia = LayerFilter(kind: .sepia)
        // Black and white last leaves grey; sepia last tints the grey brown.
        #expect(isGrey(layer([sepia, mono]).renderedImage, x: 6, y: 1))
        #expect(!isGrey(layer([mono, sepia]).renderedImage, x: 6, y: 1))
    }

    @Test func everyKindRunsAndKeepsTheSize() {
        let source = Layer(
            name: "Big", image: LayerImage(TestImages.halves(width: 64, height: 32)),
            canvasSize: CGSize(width: 64, height: 32)
        )
        for kind in LayerFilter.Kind.allCases {
            var filtered = source
            filtered.filters = [LayerFilter(kind: kind)]
            let image = filtered.renderedImage
            #expect(image.width == 64 && image.height == 32, "\(kind)")
        }
    }

    @Test func mosaicMakesBlocks() {
        let source = TestImages.halves(width: 200, height: 100)
        var filter = LayerFilter(kind: .mosaic)
        filter.amount = 1
        var mosaic = Layer(name: "M", image: LayerImage(source), canvasSize: CGSize(width: 200, height: 100))
        mosaic.filters = [filter]
        let image = mosaic.renderedImage
        // Neighbouring pixels inside one cell are the same colour.
        #expect(TestImages.pixel(image, x: 2, y: 2) == TestImages.pixel(image, x: 4, y: 4))
    }

    @Test func filtersAreSavedWithTheDocument() throws {
        var filter = LayerFilter(kind: .motionBlur)
        filter.angle = 30
        var off = LayerFilter(kind: .sepia)
        off.isEnabled = false
        let composition = Composition(size: size, layers: [layer([filter, off])])
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).easel")
        try CompositionArchive.fileWrapper(for: composition).write(to: url, originalContentsURL: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let read = try CompositionArchive.composition(from: FileWrapper(url: url))
        #expect(read.layers[0].filters == [filter, off])
    }

    @Test func applyingFiltersPaintsThemIn() {
        var composition = Composition(size: size, layers: [layer([LayerFilter(kind: .blackAndWhite)])])
        composition.rasterize(composition.layers[0].id)
        #expect(composition.layers[0].filters.isEmpty)
        #expect(isGrey(composition.layers[0].image.cgImage, x: 1, y: 1))
    }

    @Test func aligningForPaintKeepsFilters() {
        var moved = layer([LayerFilter(kind: .blackAndWhite)])
        moved.transform.position.x += 1
        let aligned = moved.aligned(in: size)
        #expect(aligned.isAligned(to: size))
        #expect(aligned.filters.count == 1)
        // The pixels underneath are still in colour.
        #expect(TestImages.isRed(aligned.image.cgImage, x: 2, y: 1))
    }

    @Test func draggingAFilterSliderIsOneUndoStep() {
        let before = Composition(size: size, layers: [layer([LayerFilter(kind: .gaussianBlur)])])
        var after = before
        after.layers[0].filters[0].amount = 0.8
        #expect(EditScope(from: before, to: after).coalesces)

        var toggled = before
        toggled.layers[0].filters[0].isEnabled = false
        #expect(!EditScope(from: before, to: toggled).coalesces)
    }
}

@MainActor
@Suite("Layer filter commands")
struct LayerFilterCommandTests {
    @Test func addReorderToggleRemove() throws {
        let state = EditorState()
        var published = Composition.blank(size: CGSize(width: 10, height: 10))
        state.attach(to: published) { published = $0 }
        state.addFilter(.sepia)
        state.addFilter(.mosaic)
        #expect(published.layers[0].filters.map(\.kind) == [.sepia, .mosaic])

        state.moveFilters(from: [1], to: 0)
        #expect(published.layers[0].filters.map(\.kind) == [.mosaic, .sepia])

        let sepia = try #require(published.layers[0].filters.last)
        state.updateFilter(sepia.id) { $0.isEnabled = false }
        #expect(published.layers[0].activeFilters.map(\.kind) == [.mosaic])

        state.removeFilter(sepia.id)
        #expect(published.layers[0].filters.map(\.kind) == [.mosaic])
    }

    @Test func paintingAFilteredLayerKeepsItsFilters() async throws {
        let state = EditorState()
        var published = Composition.blank(size: CGSize(width: 20, height: 20))
        state.attach(to: published) { published = $0 }
        state.addFilter(.blackAndWhite)
        state.tool = .brush
        state.toolBegan(at: CGPoint(x: 2, y: 10), pressure: 1)
        state.toolMoved(to: [StrokePoint(location: CGPoint(x: 18, y: 10))])
        state.toolEnded(isTap: false, at: CGPoint(x: 18, y: 10))
        for _ in 0..<100 where state.isBusy { try await Task.sleep(for: .milliseconds(20)) }
        #expect(published.layers[0].filters.count == 1)
        #expect(TestImages.pixel(published.layers[0].image.cgImage, x: 10, y: 10).red < 50)
    }
}
