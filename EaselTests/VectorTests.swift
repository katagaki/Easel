import CoreGraphics
import Foundation
import Testing
@testable import Easel

@Suite("Vector layers")
struct VectorLayerTests {
    private let red = RGBAColor(red: 1, green: 0, blue: 0)

    private func square(fill: Bool = true) -> Layer {
        let spec = ShapeSpec(kind: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 30, y: 30),
                             isFilled: fill, lineWidth: 4, color: red)
        return Layer.vector(VectorPath.shape(spec), name: "Square")
    }

    @Test func shapesBecomeVectorLayersInPlace() {
        let layer = square()
        #expect(layer.isVector)
        let image = CompositionRenderer.render(Composition(size: CGSize(width: 40, height: 40), layers: [layer]))
        #expect(TestImages.isRed(image, x: 20, y: 20))
        #expect(TestImages.isClear(image, x: 5, y: 5))
        #expect(TestImages.isClear(image, x: 35, y: 35))
    }

    @Test func ellipsesAreFourSmoothPoints() throws {
        let spec = ShapeSpec(kind: .ellipse, start: .zero, end: CGPoint(x: 40, y: 20), isFilled: true, lineWidth: 1, color: red)
        let path = try #require(VectorPath.shape(spec).first)
        #expect(path.nodes.count == 4)
        #expect(path.nodes.allSatisfy { $0.isSmooth })
        let box = path.cgPath.boundingBoxOfPath
        #expect(abs(box.width - 40) < 0.5 && abs(box.height - 20) < 0.5)
    }

    @Test func editingPathsKeepsTheRestInPlace() throws {
        var layer = square()
        var content = try #require(layer.vector)
        // Drag one corner out past the old edge.
        content.paths[0].nodes[2].point.x += 20
        layer.setVector(content)
        let image = CompositionRenderer.render(Composition(size: CGSize(width: 60, height: 40), layers: [layer]))
        // The untouched corner is still at the top left.
        #expect(TestImages.isRed(image, x: 12, y: 12))
        #expect(TestImages.isClear(image, x: 8, y: 8))
        // The moved corner reaches further right.
        #expect(TestImages.isRed(image, x: 47, y: 29))
    }

    @Test func vectorsAreSaved() throws {
        let layer = square(fill: false)
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).easel")
        try CompositionArchive.fileWrapper(for: Composition(size: CGSize(width: 40, height: 40), layers: [layer]))
            .write(to: url, originalContentsURL: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let read = try CompositionArchive.composition(from: FileWrapper(url: url))
        #expect(read.layers[0].vector == layer.vector)
    }

    @Test func paintingTurnsAVectorIntoPixels() {
        let layer = square()
        let aligned = layer.aligned(in: CGSize(width: 40, height: 40))
        #expect(aligned.vector == nil)
        #expect(aligned.isAligned(to: CGSize(width: 40, height: 40)))
    }

    @Test func resizingRedrawsVectorsSharply() throws {
        var composition = Composition(size: CGSize(width: 40, height: 40), layers: [square()])
        composition.resizeImage(to: CGSize(width: 80, height: 80))
        let layer = composition.layers[0]
        #expect(abs(layer.transform.scaleX - 1) < 0.0001)
        #expect(layer.image.width > 40)
        let image = CompositionRenderer.render(composition)
        #expect(TestImages.isRed(image, x: 40, y: 40))
        #expect(TestImages.isClear(image, x: 15, y: 15))
    }
}
