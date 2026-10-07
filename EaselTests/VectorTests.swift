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

@MainActor
@Suite("Pen tool")
struct PenToolTests {
    private func editor() -> EditorState {
        let state = EditorState()
        state.attach(to: .blank(size: CGSize(width: 200, height: 200))) { _ in }
        state.viewportSize = CGSize(width: 400, height: 400)
        state.tool = .pen
        state.shapeLineWidth = 4
        return state
    }

    private func tap(_ state: EditorState, _ x: Double, _ y: Double) {
        state.toolBegan(at: CGPoint(x: x, y: y), pressure: 1)
        state.toolEnded(isTap: true, at: CGPoint(x: x, y: y))
    }

    @Test func tapsMakeCornersAndTheFirstPointCloses() throws {
        let state = editor()
        tap(state, 20, 20)
        tap(state, 120, 20)
        tap(state, 120, 120)
        let layer = try #require(state.activeLayer)
        #expect(layer.isVector)
        #expect(layer.vector?.paths.first?.nodes.count == 3)
        tap(state, 21, 21)
        #expect(state.penPath == nil)
        let path = try #require(state.activeLayer?.vector?.paths.first)
        #expect(path.isClosed)
        #expect(path.nodes.count == 3)
        // The corner points sit where they were tapped on the canvas.
        let corner = path.nodes[1].point.applying(state.activeLayer!.affineTransform)
        #expect(abs(corner.x - 120) < 0.01 && abs(corner.y - 20) < 0.01)
    }

    @Test func draggingMakesASmoothCurve() throws {
        let state = editor()
        tap(state, 20, 100)
        state.toolBegan(at: CGPoint(x: 100, y: 100), pressure: 1)
        state.toolMoved(to: [StrokePoint(location: CGPoint(x: 140, y: 100))])
        state.toolEnded(isTap: false, at: CGPoint(x: 140, y: 100))
        let layer = try #require(state.activeLayer)
        let node = try #require(layer.vector?.paths.first?.nodes.last)
        #expect(node.isSmooth)
        let out = try #require(node.controlOut).applying(layer.affineTransform)
        let into = try #require(node.controlIn).applying(layer.affineTransform)
        #expect(abs(out.x - 140) < 0.01)
        #expect(abs(into.x - 60) < 0.01)
    }

    @Test func finishingLeavesThePathOpen() throws {
        let state = editor()
        tap(state, 20, 20)
        tap(state, 80, 80)
        state.finishPath()
        tap(state, 150, 150)
        // A new path on a new layer.
        #expect(state.composition.layers.filter(\.isVector).count == 2)
    }
}
