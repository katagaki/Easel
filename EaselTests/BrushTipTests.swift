import CoreGraphics
import Foundation
import Testing
@testable import Easel

@Suite("Brush tips")
struct BrushTipTests {
    private func stroke(_ tip: BrushTip, size: Double = 10, from: CGPoint = CGPoint(x: 10, y: 20), to: CGPoint = CGPoint(x: 90, y: 20)) -> Stroke {
        var settings = BrushSettings(size: size, color: RGBAColor(red: 1, green: 0, blue: 0), usesPressure: false)
        settings.tip = tip
        return Stroke(points: [StrokePoint(location: from), StrokePoint(location: to)], settings: settings, kind: .paint)
    }

    private var canvas: CGImage { Bitmap.render(size: CGSize(width: 100, height: 40)) { _ in } }

    @Test func dabsAreSpacedByTheBrushWidth() {
        let dabs = stroke(.pencil).dabs
        // 80 pixels at 1.2 pixel steps, plus the first.
        #expect(dabs.count > 60 && dabs.count < 70)
        #expect(dabs.first?.center == CGPoint(x: 10, y: 20))
        #expect(dabs.allSatisfy { $0.diameter == 10 })
    }

    @Test func aTiltedPencilShadesBroadAndLight() {
        var tilted = stroke(.pencil)
        tilted.points = tilted.points.map { var point = $0; point.altitude = 0.2; point.azimuth = 0; return point }
        let upright = stroke(.pencil).dabs[0], flat = tilted.dabs[0]
        #expect(flat.diameter > upright.diameter * 1.8)
        #expect(flat.opacity < upright.opacity)
        tilted.settings.usesTilt = false
        #expect(tilted.dabs[0].diameter == upright.diameter)
    }

    @Test func aCalligraphyNibTurnsWithThePencil() {
        var leaning = stroke(.calligraphy)
        leaning.points = leaning.points.map { var point = $0; point.azimuth = 0.3; point.altitude = 0.8; return point }
        #expect(abs(leaning.dabs[0].angle - (0.3 + .pi / 2)) < 0.0001)
        // A finger keeps the usual slant.
        #expect(stroke(.calligraphy).dabs[0].angle == BrushTip.nibAngle)
    }

    @Test func dabsComeOutTheSameEachTime() {
        #expect(stroke(.chalk).dabs == stroke(.chalk).dabs)
    }

    @Test func aCalligraphyNibIsThinOneWayAndBroadTheOther() {
        // Drawn along the nib's slant the line is thin; across it, broad.
        let along = Painter.paint(stroke(.calligraphy, size: 20, from: CGPoint(x: 20, y: 5), to: CGPoint(x: 50, y: 35)), onto: canvas)
        let across = Painter.paint(stroke(.calligraphy, size: 20, from: CGPoint(x: 50, y: 5), to: CGPoint(x: 20, y: 35)), onto: canvas)
        func inked(_ image: CGImage) -> Int {
            var count = 0
            for y in 0..<40 { for x in 0..<100 where TestImages.pixel(image, x: x, y: y).alpha > 128 { count += 1 } }
            return count
        }
        #expect(inked(across) > inked(along) * 2)
    }

    @Test func pencilAndChalkLeaveGrainWhereRoundIsSolid() {
        func solidShare(_ tip: BrushTip) -> Double {
            let image = Painter.paint(stroke(tip, size: 16), onto: canvas)
            let samples = (20..<80).map { TestImages.pixel(image, x: $0, y: 20).alpha }
            return Double(samples.filter { $0 > 250 }.count) / Double(samples.count)
        }
        #expect(solidShare(.round) > 0.95)
        #expect(solidShare(.pencil) < 0.9)
        // Chalk skips more of the paper than pencil.
        func coverage(_ tip: BrushTip) -> Double {
            let image = Painter.paint(stroke(tip, size: 16), onto: canvas)
            return (20..<80).map { TestImages.pixel(image, x: $0, y: 20).alpha }.reduce(0, +)
        }
        #expect(coverage(.chalk) < coverage(.pencil))
    }

    @Test func charcoalIsBrokenAndShadesOnItsSide() {
        let image = Painter.paint(stroke(.charcoal, size: 16), onto: canvas)
        let samples = (20..<80).map { TestImages.pixel(image, x: $0, y: 20).alpha }
        #expect(samples.contains { $0 > 200 })
        #expect(samples.contains { $0 < 150 })
        // Its dabs wander a little off the line.
        #expect(stroke(.charcoal).dabs.contains { abs($0.center.y - 20) > 0.2 })
        var tilted = stroke(.charcoal)
        tilted.points = tilted.points.map { var point = $0; point.altitude = 0.2; point.azimuth = 0; return point }
        #expect(tilted.dabs[0].diameter > stroke(.charcoal).dabs[0].diameter * 1.8)
    }

    @Test func crayonLeavesThePapersHollowsBare() {
        let image = Painter.paint(stroke(.crayon, size: 16), onto: canvas)
        let samples = (20..<80).flatMap { x in (16..<24).map { TestImages.pixel(image, x: x, y: $0).alpha } }
        // Full wax on the peaks, next to nothing in the hollows.
        #expect(samples.contains { $0 > 240 })
        #expect(samples.contains { $0 < 90 })
        // Coarser than a pencil's grain: the bare patches run wider.
        #expect(stroke(.crayon).grainScale > stroke(.pencil).grainScale)
    }

    @Test func stipplingLeavesSeparateDots() {
        let dabs = stroke(.stipple, size: 20).dabs
        // Small dots, varied, spread across the stroke's width.
        #expect(dabs.allSatisfy { $0.diameter <= 8 })
        #expect(Set(dabs.map(\.diameter)).count > 5)
        #expect(dabs.contains { abs($0.center.y - 20) > 3 })
        // Painted, the line breaks between them.
        let image = Painter.paint(stroke(.stipple, size: 20), onto: canvas)
        let row = (15..<85).map { TestImages.pixel(image, x: $0, y: 20).alpha }
        #expect(row.contains { $0 > 200 })
        #expect(row.filter { $0 == 0 }.count > 10)
    }

    @Test func airbrushBuildsUpSoftly() {
        let image = Painter.paint(stroke(.airbrush, size: 20), onto: canvas)
        let middle = TestImages.pixel(image, x: 50, y: 20).alpha
        let edge = TestImages.pixel(image, x: 50, y: 27).alpha
        #expect(middle > 100)
        #expect(edge < middle)
    }

    @Test func aMarkerDarkensWhatItCrosses() {
        // Yellow under a cyan marker comes out green, as felt ink does. (The
        // layer is Display P3, where sRGB cyan has some red.)
        let yellow = Bitmap.solid(size: CGSize(width: 100, height: 40), color: RGBAColor(red: 1, green: 1, blue: 0))
        var marker = stroke(.marker, size: 16)
        marker.settings.color = RGBAColor(red: 0, green: 1, blue: 1)
        let crossed = TestImages.pixel(Painter.paint(marker, onto: yellow), x: 50, y: 20)
        #expect(crossed.red < 130 && crossed.green > 200 && crossed.blue < 100, "\(crossed)")
        // On an empty layer it is simply its own colour.
        let alone = TestImages.pixel(Painter.paint(marker, onto: canvas), x: 50, y: 20)
        #expect(alone.red < 130 && alone.green > 200 && alone.blue > 200 && alone.alpha > 250, "\(alone)")
    }

    @Test func aMarkerIsAChiselLikeACalligraphyNib() {
        func inked(from: CGPoint, to: CGPoint) -> Int {
            let image = Painter.paint(stroke(.marker, size: 20, from: from, to: to), onto: canvas)
            var count = 0
            for y in 0..<40 { for x in 0..<100 where TestImages.pixel(image, x: x, y: y).alpha > 128 { count += 1 } }
            return count
        }
        #expect(inked(from: CGPoint(x: 50, y: 5), to: CGPoint(x: 20, y: 35)) > inked(from: CGPoint(x: 20, y: 5), to: CGPoint(x: 50, y: 35)) * 3 / 2)
    }

    @Test func aStampedEraserCutsThrough() {
        var eraser = stroke(.pencil, size: 16)
        eraser.kind = .erase
        let solid = Bitmap.solid(size: CGSize(width: 100, height: 40), color: .black)
        let result = Painter.paint(eraser, onto: solid)
        #expect(TestImages.pixel(result, x: 50, y: 20).alpha < 200)
        #expect(TestImages.pixel(result, x: 50, y: 2).alpha > 250)
    }
}

@MainActor
@Suite("Brush presets")
struct BrushPresetTests {
    @Test func aPresetChangesTheBrushButKeepsItsColour() {
        var settings = BrushSettings(size: 10, color: RGBAColor(red: 0, green: 0, blue: 1))
        settings.tip = .chalk
        let pastel = BrushPreset(name: "Mine", settings: settings)
        let ink = BrushSettings(size: 3, color: RGBAColor(red: 1, green: 0, blue: 0))
        let applied = pastel.applied(to: ink)
        #expect(applied.tip == .chalk)
        #expect(applied.size == 10)
        #expect(applied.color == ink.color)
    }

    @Test func theBuiltInBrushesAreEachDifferent() {
        #expect(Set(BrushPreset.builtIn.map(\.tip)).count == BrushPreset.builtIn.count)
    }

    @Test func savedBrushesAreKeptBetweenLaunches() throws {
        let suite = "BrushPresetTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = BrushSettings(size: 42)
        settings.tip = .airbrush
        let library = BrushLibrary(defaults: defaults)
        library.save(settings, as: "  Haze  ")
        library.save(settings, as: "   ")
        let reopened = BrushLibrary(defaults: defaults)
        #expect(reopened.saved.map(\.name) == ["Haze"])
        #expect(reopened.saved.first?.size == 42)
        reopened.delete(try #require(reopened.saved.first))
        #expect(BrushLibrary(defaults: defaults).saved.isEmpty)
    }
}
