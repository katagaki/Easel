import CoreGraphics
import Foundation
import Testing
@testable import Easel

@Suite("Brush dynamics")
struct BrushDynamicsTests {
    /// A stroke along y = 20 from x = 10 to 190, sampled every 10 pixels.
    private func stroke(_ tip: BrushTip = .round, size: Double = 10, _ change: (inout BrushDynamics) -> Void) -> Stroke {
        var settings = BrushSettings(size: size, color: RGBAColor(red: 1, green: 0, blue: 0), usesPressure: false)
        settings.tip = tip
        change(&settings.dynamics)
        let points = stride(from: 10.0, through: 190, by: 10).map { StrokePoint(location: CGPoint(x: $0, y: 20)) }
        return Stroke(points: points, settings: settings, kind: .paint)
    }

    private var canvas: CGImage { Bitmap.render(size: CGSize(width: 200, height: 40)) { _ in } }

    /// How many pixels down column `x` are inked.
    private func thickness(_ image: CGImage, x: Int) -> Int {
        (0..<40).filter { TestImages.pixel(image, x: x, y: $0).alpha > 128 }.count
    }

    @Test func aTaperThinsBothEndsAndLeavesTheMiddle() {
        let widths = stroke { $0.taper = 0.5 }.widths
        #expect(widths.first! < 2)
        #expect(widths.last! < 2)
        #expect(widths[widths.count / 2] == 10)
        // Widening steadily out of the point.
        #expect(widths[1] > widths[0] && widths[2] > widths[1])
        #expect(stroke { $0.taper = 0 }.widths.allSatisfy { $0 == 10 })
    }

    @Test func aShortStrokeStillReachesFullWidthInTheMiddle() {
        var short = stroke { $0.taper = 1 }
        short.points = [CGPoint(x: 10, y: 20), CGPoint(x: 15, y: 20), CGPoint(x: 20, y: 20)].map { StrokePoint(location: $0) }
        #expect(short.widths[1] == 10)
    }

    @Test func aTaperedLineIsPaintedFineAtItsEnds() {
        let image = Painter.paint(stroke { $0.taper = 0.5 }, onto: canvas)
        #expect(thickness(image, x: 100) >= 9)
        #expect(thickness(image, x: 13) < 5)
        let stamped = Painter.paint(stroke(.pencil) { $0.taper = 0.5 }, onto: canvas)
        #expect(thickness(stamped, x: 13) < thickness(stamped, x: 100))
    }

    @Test func aQuickStrokeThinsWhereItHurries() {
        // Slow for the first half, ten pixels each 0.1 s; then ten pixels
        // each millisecond.
        var hurried = stroke { $0.speed = 1 }
        var time = 0.0
        hurried.points = hurried.points.enumerated().map { index, point in
            var timed = point
            time += index < 10 ? 0.1 : 0.001
            timed.time = time
            return timed
        }
        let widths = hurried.widths
        #expect(widths[1] > 9)
        #expect(widths[widths.count - 2] < 5)
        // Untimed points, as from a ruler or a test, keep their width.
        #expect(stroke { $0.speed = 1 }.widths.allSatisfy { $0 == 10 })
        hurried.settings.dynamics.speed = 0
        #expect(hurried.widths.allSatisfy { $0 == 10 })
    }

    @Test func brushesSavedBeforeDynamicsStillOpen() throws {
        let old = #"{"id":"6E1A6C4C-0E5B-4C8B-9E83-2B0A0B0B0B0B","name":"Old","tip":"round","size":5,"opacity":1,"softness":0,"usesPressure":true,"usesTilt":true}"#
        let preset = try JSONDecoder().decode(BrushPreset.self, from: Data(old.utf8))
        #expect(preset.applied(to: BrushSettings(size: 1)).dynamics == BrushDynamics())
        let empty = try JSONDecoder().decode(BrushDynamics.self, from: Data("{}".utf8))
        #expect(empty == BrushDynamics())
    }

    @Test func aPresetKeepsItsDynamics() {
        var settings = BrushSettings(size: 10)
        settings.dynamics.taper = 0.7
        #expect(BrushPreset(name: "Tapered", settings: settings).applied(to: BrushSettings(size: 1)).dynamics.taper == 0.7)
    }
}
