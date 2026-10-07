import CoreGraphics
import Testing
@testable import Easel

@Suite("Pixel selections")
struct SelectionMaskTests {
    /// The left half of an 8 by 4 canvas.
    private func leftHalf() -> SelectionMask {
        var bytes = [UInt8](repeating: 0, count: 32)
        for y in 0..<4 { for x in 0..<4 { bytes[y * 8 + x] = 255 } }
        return SelectionMask(bytes: bytes, width: 8, height: 4)!
    }

    @Test func emptyMasksSelectNothing() {
        #expect(SelectionMask(bytes: [UInt8](repeating: 0, count: 16), width: 4, height: 4) == nil)
    }

    @Test func boundsCoverTheSelectedPixels() {
        #expect(leftHalf().bounds == CGRect(x: 0, y: 0, width: 4, height: 4))
    }

    @Test func clearingThroughAMaskIsExact() {
        let selection = Selection(shape: .mask(leftHalf()))
        let cleared = Painter.clear(selection, in: TestImages.halves())
        #expect(TestImages.isClear(cleared, x: 1, y: 1))
        #expect(TestImages.isClear(cleared, x: 3, y: 3))
        #expect(TestImages.isBlue(cleared, x: 4, y: 0))
    }

    @Test func invertedMasksSelectTheRest() {
        let selection = Selection(shape: .mask(leftHalf()), isInverted: true)
        let cleared = Painter.clear(selection, in: TestImages.halves())
        #expect(TestImages.isRed(cleared, x: 1, y: 1))
        #expect(TestImages.isClear(cleared, x: 6, y: 1))
        #expect(selection.coverage(width: 8, height: 4)[0] == 0)
    }

    @Test func outlinesFollowTheEdge() {
        let outlines = leftHalf().outlines
        #expect(outlines.count == 1)
        let xs = outlines[0].map(\.x)
        #expect(xs.min()! <= 0.6 && xs.max()! >= 3.4 && xs.max()! <= 4.6)
    }

    @Test func masksMoveWithTheCanvas() throws {
        let selection = Selection(shape: .mask(leftHalf()))
        let flipped = selection.applying(
            CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 8, ty: 0), canvasSize: CGSize(width: 8, height: 4)
        )
        guard case .mask(let mask) = flipped.shape else { Issue.record("not a mask"); return }
        #expect(mask.bounds == CGRect(x: 4, y: 0, width: 4, height: 4))
    }

    @Test func magicSelectPicksTheColourAroundTheTap() throws {
        let size = CGSize(width: 8, height: 4)
        let composition = Composition(size: size, layers: [
            Layer(name: "Halves", image: LayerImage(TestImages.halves()), canvasSize: size),
        ])
        let mask = try #require(EditorState.colourRegion(in: composition, at: CGPoint(x: 6, y: 1), tolerance: 0.1))
        #expect(mask.bounds == CGRect(x: 4, y: 0, width: 4, height: 4))
    }
}
