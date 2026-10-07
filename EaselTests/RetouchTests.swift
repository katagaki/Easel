import CoreGraphics
import Testing
@testable import Easel

@Suite("Retouching")
struct RetouchTests {
    private func line(_ kind: Stroke.Kind, size: Double = 6, from: CGPoint, to: CGPoint, strength: Double = 1) -> Stroke {
        Stroke(
            points: [StrokePoint(location: from), StrokePoint(location: to)],
            settings: BrushSettings(size: size, opacity: strength, usesPressure: false), kind: kind
        )
    }

    /// Red on the left, blue on the right, 40 by 20.
    private var halves: CGImage { TestImages.halves(width: 40, height: 20) }

    @Test func blurBrushSoftensOnlyWhereItGoes() {
        let stroke = line(.blur, size: 8, from: CGPoint(x: 20, y: 2), to: CGPoint(x: 20, y: 18))
        let effect = RetouchEffect.image(.blur, settings: stroke.settings, of: halves)
        let result = Painter.apply(effect, onto: halves, through: stroke)
        // At the seam, red and blue mix.
        let seam = TestImages.pixel(result, x: 20, y: 10)
        #expect(seam.red > 40 && seam.blue > 40)
        // Away from the stroke, untouched.
        #expect(TestImages.isRed(result, x: 2, y: 10))
        #expect(TestImages.isBlue(result, x: 38, y: 10))
    }

    @Test func mosaicBrushMakesTilesOnTheCanvasGrid() {
        let source = Bitmap.render(size: CGSize(width: 40, height: 40)) { context in
            for x in 0..<40 {
                context.setFillColor(RGBAColor(red: Double(x) / 40, green: 0, blue: 0).cgColor)
                context.fill(CGRect(x: x, y: 0, width: 1, height: 40))
            }
        }
        var settings = BrushSettings(size: 40, opacity: 0.5, usesPressure: false)
        settings.softness = 0
        let cell = Int(RetouchEffect.mosaicCell(for: settings))
        let effect = RetouchEffect.image(.mosaic, settings: settings, of: source)
        // Within one tile, every pixel is the same.
        #expect(TestImages.pixel(effect, x: 0, y: 0) == TestImages.pixel(effect, x: cell - 1, y: cell - 1))
        #expect(TestImages.pixel(effect, x: 0, y: 0) != TestImages.pixel(effect, x: cell, y: 0))
    }

    @Test func smudgeDragsColourAlong() {
        let pixels = Bitmap.pixels(of: halves)!
        var smudger = Smudger(
            pixels: pixels, settings: BrushSettings(size: 8, opacity: 0.9, usesPressure: false),
            selection: nil, start: CGPoint(x: 10, y: 10)
        )
        let changed = smudger.drag(to: CGPoint(x: 30, y: 10))
        #expect(changed != nil)
        let image = smudger.pixels.makeImage()!
        // Red has been carried into the blue half.
        #expect(TestImages.pixel(image, x: 25, y: 10).red > 60)
        // Outside the brush's path, nothing moved.
        #expect(TestImages.isBlue(image, x: 30, y: 1))
    }

    @Test func smudgeStaysInsideTheSelection() {
        let pixels = Bitmap.pixels(of: halves)!
        var smudger = Smudger(
            pixels: pixels, settings: BrushSettings(size: 8, opacity: 0.9, usesPressure: false),
            selection: Selection(shape: .rectangle(CGRect(x: 0, y: 0, width: 24, height: 20))), start: CGPoint(x: 10, y: 10)
        )
        _ = smudger.drag(to: CGPoint(x: 34, y: 10))
        #expect(TestImages.isBlue(smudger.pixels.makeImage()!, x: 30, y: 10))
    }

    @Test func healCoversASpotWithItsSurroundings() {
        // A grey field with a black blemish in the middle.
        let image = Bitmap.render(size: CGSize(width: 80, height: 80)) { context in
            context.setFillColor(RGBAColor(red: 0.6, green: 0.6, blue: 0.6).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
            context.setFillColor(RGBAColor.black.cgColor)
            context.fillEllipse(in: CGRect(x: 36, y: 36, width: 8, height: 8))
        }
        let before = TestImages.pixel(image, x: 40, y: 40)
        #expect(before.red < 20)
        let stroke = line(.heal, size: 16, from: CGPoint(x: 40, y: 40), to: CGPoint(x: 40, y: 40))
        let healed = Healer.heal(image, with: stroke)
        let after = TestImages.pixel(healed, x: 40, y: 40)
        let field = TestImages.pixel(image, x: 10, y: 10)
        #expect(abs(after.red - field.red) < 25)
        // Far from the spot, unchanged.
        #expect(TestImages.pixel(healed, x: 5, y: 5) == field)
    }

    @Test func boxBlurKeepsTheAverage() {
        var values: [Float] = [0, 0, 0, 9, 0, 0, 0]
        Healer.boxBlur(&values, width: 7, height: 1, radius: 1, passes: 1)
        #expect(abs(values.reduce(0, +) - 9) < 0.01)
        #expect(values[3] == 3)
    }
}

@MainActor
@Suite("Retouch tools")
struct RetouchToolTests {
    @Test func smudgingChangesTheLayerAndKeepsFilters() throws {
        let state = EditorState()
        var composition = Composition.blank(size: CGSize(width: 40, height: 20))
        composition.layers[0].image = LayerImage(TestImages.halves(width: 40, height: 20))
        var published = composition
        state.attach(to: published) { published = $0 }
        state.addFilter(.sepia)
        state.tool = .smudge
        state.toolBegan(at: CGPoint(x: 10, y: 10), pressure: 1)
        state.toolMoved(to: [StrokePoint(location: CGPoint(x: 30, y: 10))])
        #expect(state.smudge?.patches.isEmpty == false)
        state.toolEnded(isTap: false, at: CGPoint(x: 30, y: 10))
        #expect(state.smudge == nil)
        #expect(published.layers[0].filters.count == 1)
        #expect(TestImages.pixel(published.layers[0].image.cgImage, x: 25, y: 10).red > 60)
    }

    @Test func retouchToolsKeepTheirOwnSettings() {
        let state = EditorState()
        state.tool = .blur
        state.currentBrush.size = 123
        state.tool = .brush
        #expect(state.currentBrush.size != 123)
        state.tool = .blur
        #expect(state.currentBrush.size == 123)
        #expect(state.strokeKind == .blur)
    }
}
