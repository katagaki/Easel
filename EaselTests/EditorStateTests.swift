import CoreGraphics
import Testing
@testable import Easel

@MainActor
@Suite("Editor")
struct EditorStateTests {
    /// An editor on its own, its edits kept in `published`.
    @MainActor
    private final class Host {
        let state = EditorState()
        var published: Composition

        init(_ composition: Composition) {
            published = composition
            state.attach(to: composition) { [unowned self] in self.published = $0 }
        }
    }

    @Test func aFirstPictureTakesTheUntouchedCanvasesPlace() {
        let host = Host(.blank(size: CGSize(width: 100, height: 100)))
        host.state.addImageLayers([(TestImages.halves(width: 40, height: 20), "Photo")])
        #expect(host.state.activeLayerID == host.published.layers.first?.id)
        host.state.addImageLayers([(TestImages.halves(), "Second")])
        #expect(host.published.size == CGSize(width: 40, height: 20))
        #expect(host.published.layers.map(\.name) == ["Photo", "Second"])
        #expect(host.state.activeLayerID == host.published.layers.last?.id)
        #expect(host.state.tool == .move)
    }

    @Test func picturesStackOnADrawnCanvas() {
        var composition = Composition.blank(size: CGSize(width: 100, height: 100))
        composition.layers[0].image = LayerImage(TestImages.solid(.white, width: 100, height: 100))
        let host = Host(composition)
        host.state.addImageLayers([(TestImages.halves(width: 400, height: 200), "Big")])
        #expect(host.published.size == CGSize(width: 100, height: 100))
        #expect(host.published.layers.count == 2)
        // Shrunk to fit, by scale rather than by resampling.
        #expect(host.published.layers[1].transform.scaleX == 0.25)
    }

    @Test func editsInARowEachSeeTheOneBefore() {
        let host = Host(.blank(size: CGSize(width: 10, height: 10)))
        host.state.addEmptyLayer()
        host.state.addEmptyLayer()
        #expect(host.published.layers.count == 3)
        #expect(Set(host.published.layers.map(\.name)).count == 3)
    }

    @Test func theLastLayerCannotBeDeleted() {
        let host = Host(.blank(size: CGSize(width: 10, height: 10)))
        let only = host.published.layers[0].id
        host.state.deleteLayer(only)
        #expect(host.published.layers.count == 1)
    }

    @Test func reorderingFromTheTopFirstList() {
        let host = Host(.blank(size: CGSize(width: 10, height: 10)))
        host.state.addEmptyLayer()
        let bottom = host.published.layers[0].id
        // Shown top first, the background is row 1; drag it above row 0.
        host.state.moveLayers(fromDisplayed: [1], toDisplayed: 0)
        #expect(host.published.layers.last?.id == bottom)
    }

    @Test func lockedLayersRefusePaint() {
        let host = Host(.blank(size: CGSize(width: 10, height: 10)))
        host.state.setLocked(true, of: host.published.layers[0].id)
        host.state.tool = .brush
        host.state.toolBegan(at: CGPoint(x: 1, y: 1), pressure: 1)
        #expect(host.state.activeStroke == nil)
        #expect(host.state.paintingBlocker() != nil)
    }

    @Test func aTapWithTheSelectionToolDeselects() {
        let host = Host(.blank(size: CGSize(width: 10, height: 10)))
        host.state.selectAll()
        host.state.tool = .select
        host.state.toolBegan(at: CGPoint(x: 2, y: 2), pressure: 1)
        host.state.toolEnded(isTap: true, at: CGPoint(x: 2, y: 2))
        #expect(host.state.selection == nil)
    }

    @Test func draggingTheSelectionToolSelects() {
        let host = Host(.blank(size: CGSize(width: 10, height: 10)))
        host.state.tool = .select
        host.state.toolBegan(at: CGPoint(x: 1, y: 1), pressure: 1)
        host.state.toolMoved(to: [StrokePoint(location: CGPoint(x: 6, y: 5))])
        host.state.toolEnded(isTap: false, at: CGPoint(x: 6, y: 5))
        #expect(host.state.selection?.bounds(in: CGSize(width: 10, height: 10)) == CGRect(x: 1, y: 1, width: 5, height: 4))
    }

    @Test func movingDragsTheLayer() {
        let host = Host(.blank(size: CGSize(width: 10, height: 10)))
        host.state.tool = .move
        host.state.toolBegan(at: CGPoint(x: 2, y: 2), pressure: 1)
        host.state.toolMoved(to: [StrokePoint(location: CGPoint(x: 5, y: 6))])
        host.state.toolEnded(isTap: false, at: CGPoint(x: 5, y: 6))
        #expect(host.published.layers[0].transform.position == CGPoint(x: 8, y: 9))
    }

    @Test func cropToolKeepsItsFrameOnTheCanvas() {
        let host = Host(.blank(size: CGSize(width: 100, height: 50)))
        host.state.tool = .crop
        #expect(host.state.cropRect == CGRect(x: 0, y: 0, width: 100, height: 50))
        host.state.cropAspect = .square
        #expect(host.state.cropRect?.width == host.state.cropRect?.height)
        host.state.applyCrop()
        #expect(host.published.size == CGSize(width: 50, height: 50))
    }

    @Test func textToolStartsAnEditableLayer() throws {
        let host = Host(.blank(size: CGSize(width: 200, height: 200)))
        host.state.tool = .text
        host.state.toolEnded(isTap: true, at: CGPoint(x: 100, y: 100))
        let layer = try #require(host.state.activeLayer)
        #expect(layer.isText)
        #expect(host.state.presentedPanel == .text)
        host.state.updateText { $0.string = "Easel" }
        #expect(host.published.layers.last?.text?.string == "Easel")
        #expect(host.published.layers.last?.name == "Easel")
    }

    @Test func viewportMapsCanvasPointsBothWays() {
        let viewport = CanvasViewport(
            canvasSize: CGSize(width: 200, height: 100), viewportSize: CGSize(width: 432, height: 332),
            insets: .init(), zoom: 2, pan: CGSize(width: 10, height: -5)
        )
        let point = CGPoint(x: 37, y: 81)
        let back = viewport.canvasPoint(viewport.screenPoint(point))
        #expect(abs(back.x - point.x) < 0.0001 && abs(back.y - point.y) < 0.0001)
        #expect(viewport.scale == 4)
    }
}

@Suite("Undo")
struct EditScopeTests {
    @Test func sliderDragsOnOneLayerCoalesce() {
        var before = Composition.blank(size: CGSize(width: 4, height: 4))
        before.layers[0].opacity = 0.9
        var after = before
        after.layers[0].opacity = 0.5
        let scope = EditScope(from: before, to: after)
        #expect(scope.kind == .opacity)
        #expect(scope.coalesces)
    }

    @Test func structuralChangesAreStepsOfTheirOwn() {
        let before = Composition.blank(size: CGSize(width: 4, height: 4))
        var after = before
        after.layers.append(before.emptyLayer())
        #expect(!EditScope(from: before, to: after).coalesces)
    }
}

@MainActor
@Suite("Text tool")
struct TextToolTests {
    @Test func tapsOffThePictureAddNoText() {
        let state = EditorState()
        state.attach(to: .blank(size: CGSize(width: 100, height: 100))) { _ in }
        state.tool = .text
        state.toolEnded(isTap: true, at: CGPoint(x: 50, y: 400))
        #expect(state.composition.layers.count == 1)
        #expect(state.presentedPanel == nil)
    }
}
