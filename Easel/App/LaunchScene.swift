import SwiftUI

/// The pieces of the document picker's top area: a pink wash laid over the
/// checkerboard an empty canvas shows, with a wall of the app's tools behind
/// the actions.
enum DocumentLaunch {
    /// A wash of the app icon's pink, kept quiet: near white in light mode,
    /// near black in dark, so the system's buttons and browser read over it.
    static let topColor = adaptive(
        light: UIColor(red: 0.99, green: 0.89, blue: 0.92, alpha: 1),
        dark: UIColor(red: 0.22, green: 0.07, blue: 0.11, alpha: 1)
    )
    static let bottomColor = adaptive(
        light: UIColor(red: 1.00, green: 0.97, blue: 0.98, alpha: 1),
        dark: UIColor(red: 0.09, green: 0.04, blue: 0.05, alpha: 1)
    )
    /// The colour the checkerboard is drawn in.
    static let ink = adaptive(
        light: UIColor(red: 0.85, green: 0.22, blue: 0.38, alpha: 1),
        dark: UIColor(red: 0.80, green: 0.42, blue: 0.53, alpha: 1)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// The pink wash, checkered faintly like a transparent canvas, fading out
/// towards the browser so the pattern never competes with file names.
struct DocumentLaunchBackground: View {
    private let squareSize = 14.0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DocumentLaunch.topColor, DocumentLaunch.bottomColor],
                startPoint: .top,
                endPoint: .bottom
            )
            Canvas { context, size in
                var squares = Path()
                var row = 0
                var y = 0.0
                while y < size.height {
                    var x = row.isMultiple(of: 2) ? 0 : squareSize
                    while x < size.width {
                        squares.addRect(CGRect(x: x, y: y, width: squareSize, height: squareSize))
                        x += squareSize * 2
                    }
                    y += squareSize
                    row += 1
                }
                context.fill(squares, with: .color(DocumentLaunch.ink.opacity(0.06)))
            }
            .mask {
                LinearGradient(
                    colors: [.white, .white.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// A wall of small tiles, each something a picture can be made with —
/// brushes, swatches, layers, paths, selections, gradients, curves and
/// filters — laid in staggered rows across the whole header. It sits behind
/// the buttons, faded so it reads as a backdrop rather than content.
/// Decoration only, so hidden from VoiceOver.
struct DocumentLaunchToolWall: View {
    let geometry: DocumentLaunchGeometryProxy

    private enum Tile {
        case stroke(Brush, Color)
        case swatches, layers, path, selection, gradient, colorWheel
        case curves, histogram, symmetry, type, picture
        case symbol(String, Color)
    }

    private enum Brush {
        case round, pencil, calligraphy, airbrush
    }

    /// No tile appears twice in a pattern, and the kinds are spread so
    /// neighbours differ. Rows start just off the leading edge, like a wall
    /// that carries on out of frame, so the most telling tiles come first,
    /// where a phone shows them.
    private let rows: [[Tile]] = [
        [.stroke(.round, .pink), .swatches, .symbol("paintbrush.pointed.fill", .orange), .path,
         .gradient, .symbol("eyedropper.halffull", .teal), .layers, .stroke(.airbrush, .purple)],
        [.picture, .stroke(.calligraphy, .indigo), .colorWheel, .symbol("lasso", .blue),
         .curves, .stroke(.pencil, .orange), .symbol("wand.and.sparkles", .purple), .selection],
        [.symbol("pencil.tip", .pink), .layers, .stroke(.airbrush, .teal), .histogram,
         .type, .symbol("drop.fill", .blue), .stroke(.round, .orange), .symmetry],
        [.stroke(.pencil, .indigo), .selection, .symbol("scribble.variable", .pink), .gradient,
         .stroke(.calligraphy, .purple), .picture, .swatches, .symbol("paintpalette.fill", .orange)],
    ]

    private let tileHeight = 44.0
    private let spacing = 8.0

    /// How far each row starts off the leading edge. Five offsets against four
    /// row patterns, so the wall does not visibly repeat on a tall screen.
    private let rowOffsets: [Double] = [-18, -46, -30, -8, -38]

    var body: some View {
        // The wall fills the launch area from the top and fades out above the
        // browser, rather than being fitted around the buttons: the system
        // places the actions and browser differently on iPhone and iPad.
        let frame = geometry.frame
        let rowCount = Int(frame.height * fadeEnd / (tileHeight + spacing)) + 1

        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<rowCount, id: \.self) { index in
                // A row's pattern repeats until it is wider than any screen,
                // and starts further along each time the patterns come round
                // again, so a tall screen does not show the same rows twice.
                let pattern = rows[index % rows.count]
                let shift = (index / rows.count * 3) % pattern.count
                let rotated = Array(pattern[shift...] + pattern[..<shift])
                let tiles = Array(repeating: rotated, count: 3).flatMap { $0 }
                HStack(spacing: spacing) {
                    ForEach(tiles.indices, id: \.self) { position in
                        tile(tiles[position])
                    }
                }
                .fixedSize()
                .offset(x: rowOffsets[index % rowOffsets.count])
            }
        }
        // Drifted inside the clip, so the wall's edges never show.
        .modifier(LaunchFloating())
        .padding(.top, spacing)
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .clipped()
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .black, location: fadeStart),
                    .init(color: .clear, location: fadeEnd),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        // Faded as one layer, so overlapping tile edges do not show through.
        .compositingGroup()
        .opacity(0.4)
        .position(x: frame.midX, y: frame.midY)
        .accessibilityHidden(true)
    }

    /// Where, down the launch area, the wall starts and finishes fading. The
    /// browser's top edge sits a little under halfway down on both iPhone and
    /// iPad, so the wall is gone by the time the browser starts.
    private let fadeStart = 0.34
    private let fadeEnd = 0.47

    @ViewBuilder
    private func tile(_ tile: Tile) -> some View {
        switch tile {
        case .stroke(let brush, let color): strokeTile(brush, color: color)
        case .swatches: swatchesTile
        case .layers: layersTile
        case .path: pathTile
        case .selection: selectionTile
        case .gradient: gradientTile
        case .colorWheel: colorWheelTile
        case .curves: curvesTile
        case .histogram: histogramTile
        case .symmetry: symmetryTile
        case .type: typeTile
        case .picture: pictureTile
        case .symbol(let name, let color): symbolTile(name, color: color)
        }
    }

    private func tile(width: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: width, height: tileHeight)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
    }

    private func symbolTile(_ name: String, color: Color) -> some View {
        tile(width: tileHeight) {
            Image(systemName: name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    // The tiles use system colours, which already adapt to dark mode.

    /// A wave painted across the tile, in the look of one of the brush tips.
    private func strokeTile(_ brush: Brush, color: Color) -> some View {
        tile(width: 76) {
            let wave = LaunchWave()
            Group {
                switch brush {
                case .round:
                    wave.stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                case .pencil:
                    ZStack {
                        wave.stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        wave.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 1.5]))
                    }
                case .calligraphy:
                    // A broad nib held at an angle: thick on the way down, thin across.
                    ZStack {
                        wave.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        wave.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .offset(x: 2.5, y: -2.5)
                        wave.stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .offset(x: 1.25, y: -1.25)
                    }
                case .airbrush:
                    wave.stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .blur(radius: 2.5)
                }
            }
            .frame(width: 52, height: 18)
        }
    }

    private var swatchesTile: some View {
        tile(width: 76) {
            HStack(spacing: -4) {
                ForEach([Color.pink, .orange, .yellow, .teal], id: \.self) { color in
                    Circle()
                        .fill(color)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 1.5))
                }
            }
        }
    }

    /// Three layers stacked and offset, the top one selected.
    private var layersTile: some View {
        tile(width: tileHeight) {
            ZStack {
                ForEach(Array(zip([0, 1, 2], [Color.purple, .blue, .pink])), id: \.0) { index, color in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.35 + 0.3 * Double(index)))
                        .frame(width: 18, height: 13)
                        .offset(x: Double(index - 1) * 4, y: Double(1 - index) * 4)
                }
            }
        }
    }

    /// A curve being drawn with the pen: anchors and the handles of the middle one.
    private var pathTile: some View {
        tile(width: 76) {
            let start = CGPoint(x: 4, y: 22)
            let middle = CGPoint(x: 26, y: 8)
            let end = CGPoint(x: 48, y: 22)
            let handles = (CGPoint(x: 14, y: 8), CGPoint(x: 38, y: 8))
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: start)
                    path.addQuadCurve(to: middle, control: CGPoint(x: 6, y: 8))
                    path.addQuadCurve(to: end, control: CGPoint(x: 46, y: 8))
                }
                .stroke(.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Path { path in
                    path.move(to: handles.0)
                    path.addLine(to: handles.1)
                }
                .stroke(.secondary, lineWidth: 1)
                ForEach([handles.0, handles.1], id: \.x) { point in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 4, height: 4)
                        .position(point)
                }
                ForEach([start, middle, end], id: \.x) { point in
                    Rectangle()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .stroke(.blue, lineWidth: 1.5)
                        .frame(width: 6, height: 6)
                        .position(point)
                }
            }
            .frame(width: 52, height: 28)
        }
    }

    /// Marching ants around an ellipse.
    private var selectionTile: some View {
        tile(width: 60) {
            ZStack {
                Ellipse()
                    .fill(Color.blue.opacity(0.12))
                Ellipse()
                    .stroke(.primary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
            }
            .frame(width: 38, height: 26)
        }
    }

    private var gradientTile: some View {
        tile(width: 60) {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .leading, endPoint: .trailing))
                .frame(width: 42, height: 22)
        }
    }

    private var colorWheelTile: some View {
        tile(width: tileHeight) {
            Circle()
                .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                .overlay {
                    Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: 12))
                }
                .frame(width: 24, height: 24)
        }
    }

    /// A tone curve lifted into an S over its grid.
    private var curvesTile: some View {
        tile(width: tileHeight) {
            ZStack {
                Path { path in
                    for step in 1..<3 {
                        let offset = Double(step) * 26 / 3
                        path.move(to: CGPoint(x: offset, y: 0))
                        path.addLine(to: CGPoint(x: offset, y: 26))
                        path.move(to: CGPoint(x: 0, y: offset))
                        path.addLine(to: CGPoint(x: 26, y: offset))
                    }
                }
                .stroke(.secondary.opacity(0.5), lineWidth: 0.5)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 26))
                    path.addCurve(to: CGPoint(x: 26, y: 0), control1: CGPoint(x: 14, y: 28), control2: CGPoint(x: 12, y: -2))
                }
                .stroke(.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .frame(width: 26, height: 26)
        }
    }

    /// A histogram of a picture's tones, as the Levels panel shows it.
    private var histogramTile: some View {
        tile(width: 76) {
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(Array([0.2, 0.35, 0.6, 0.85, 1.0, 0.7, 0.5, 0.65, 0.4, 0.25, 0.15].enumerated()), id: \.offset) { _, height in
                    Capsule()
                        .fill(LinearGradient(colors: [.pink, .purple], startPoint: .top, endPoint: .bottom))
                        .frame(width: 3, height: 24 * height)
                }
            }
            .frame(height: 24, alignment: .bottom)
        }
    }

    /// A stroke mirrored across a dashed axis.
    private var symmetryTile: some View {
        tile(width: 60) {
            HStack(spacing: 2) {
                LaunchWave()
                    .stroke(.teal, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 18, height: 18)
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 1, height: 28)
                    .mask {
                        VStack(spacing: 2) {
                            ForEach(0..<7, id: \.self) { _ in Rectangle().frame(height: 2) }
                        }
                    }
                LaunchWave()
                    .stroke(.teal, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 18, height: 18)
                    .scaleEffect(x: -1)
            }
        }
    }

    /// Letters set in a serif, as the text tool sets them.
    private var typeTile: some View {
        tile(width: tileHeight) {
            Text(verbatim: "Aa")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(.indigo)
        }
    }

    /// A small landscape: a sun over two hills under a warm sky.
    private var pictureTile: some View {
        tile(width: 60) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [.orange.opacity(0.55), .pink.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(.yellow)
                    .frame(width: 8, height: 8)
                    .position(x: 30, y: 8)
                LaunchHills()
                    .fill(.mint)
            }
            .frame(width: 40, height: 28)
            .clipShape(.rect(cornerRadius: 4))
        }
    }
}

/// A single swing up and back down across its frame, the shape a quick test
/// stroke makes.
private struct LaunchWave: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.75))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.25),
                control1: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY - rect.height * 0.5),
                control2: CGPoint(x: rect.minX + rect.width * 0.6, y: rect.maxY + rect.height * 0.5)
            )
        }
    }
}

private struct LaunchHills: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.3))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.45))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.6, y: rect.maxY - rect.height * 0.3))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.8, y: rect.maxY - rect.height * 0.45))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.2))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// A gentle drift for the whole wall, so it floats without falling out of
/// line. Held still when Reduce Motion is on.
private struct LaunchFloating: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShifted = false

    func body(content: Content) -> some View {
        content
            .offset(x: reduceMotion ? 0 : (isShifted ? -6 : 6))
            .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: isShifted)
            .onAppear { isShifted = true }
    }
}
