import SwiftUI

/// The settings of the tool in hand, in a glass bar over the canvas: above
/// the carousel on iPhone, along the bottom on iPad.
struct ToolOptionsBar: View {
    @Bindable var state: EditorState

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    options
                }
                .padding(.horizontal, 12)
                .animation(.snappy(duration: 0.2), value: state.tool)
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollClipDisabled()
        .frame(height: 52)
    }

    @ViewBuilder
    private var options: some View {
        switch state.tool {
        case .brush, .eraser, .smudge, .blur, .mosaic, .heal: brushOptions
        case .fill: fillOptions
        case .gradient: gradientOptions
        case .eyedropper: eyedropperOptions
        case .move: moveOptions
        case .select: selectOptions
        case .crop: cropOptions
        case .text: textOptions
        case .shape: shapeOptions
        }
    }

    // MARK: - Painting

    private var brushOptions: some View {
        GlassGroup {
            if state.tool == .brush { ColorWell(state: state) }
            OptionSlider(
                value: Binding(
                    get: { BrushSizeScale.position(for: state.currentBrush.size) },
                    set: { state.currentBrush.size = BrushSizeScale.size(at: $0) }
                ),
                label: "Options.Size", valueText: "\(Int(state.currentBrush.size.rounded())) px"
            )
            .accessibilityIdentifier("brushSize")
            BrushSettingsButton(state: state)
        }
    }

    private var fillOptions: some View {
        GlassGroup {
            ColorWell(state: state)
            OptionSlider(
                value: $state.fillTolerance, label: "Options.Tolerance",
                valueText: "\(Int((state.fillTolerance * 100).rounded()))%"
            )
        }
    }

    private var gradientOptions: some View {
        GlassGroup {
            ColorWell(state: state)
            OptionSlider(
                value: $state.gradientOpacity, label: "Options.Opacity",
                valueText: "\(Int((state.gradientOpacity * 100).rounded()))%"
            )
        }
    }

    private var eyedropperOptions: some View {
        GlassGroup {
            ColorWell(state: state)
            Text(state.color.hexString)
                .font(.system(size: 15, weight: .medium).monospaced())
                .padding(.trailing, 12)
                .accessibilityIdentifier("sampledColor")
        }
    }

    // MARK: - Arranging

    private var moveOptions: some View {
        let isLocked = state.activeLayer?.isLocked ?? true
        return Group {
            GlassGroup {
                GlassIconButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Options.FlipHorizontal") {
                    state.updateTransform { $0.scaleX = -$0.scaleX; $0.rotation = -$0.rotation }
                }
                GlassIconButton(symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down", label: "Options.FlipVertical") {
                    state.updateTransform { $0.scaleY = -$0.scaleY; $0.rotation = -$0.rotation }
                }
                GlassIconButton(symbol: "rotate.right", label: "Options.RotateLayer") {
                    state.updateTransform { $0.rotation = Self.normalized($0.rotation + .pi / 2) }
                }
                TransformSettingsButton(state: state)
            }
            GlassGroup {
                GlassIconButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Options.FitToCanvas") {
                    state.fitLayerToCanvas()
                }
                GlassIconButton(symbol: "arrow.counterclockwise", label: "Options.ResetTransform") {
                    state.resetTransform()
                }
            }
        }
        .disabled(isLocked)
    }

    /// An angle brought back into -π...π.
    static func normalized(_ angle: Double) -> Double {
        var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if value > .pi { value -= 2 * .pi }
        if value < -.pi { value += 2 * .pi }
        return value
    }

    private var selectOptions: some View {
        Group {
            GlassGroup {
                ForEach(SelectionKind.allCases) { kind in
                    GlassIconButton(symbol: kind.symbolName, label: kind.label, isOn: state.selectionKind == kind) {
                        state.selectionKind = kind
                    }
                    .accessibilityIdentifier("selectionKind.\(kind.rawValue)")
                }
            }
            GlassGroup {
                SelectionMenu(state: state)
            }
        }
    }

    private var cropOptions: some View {
        Group {
            GlassGroup {
                GlassMenuButton(symbol: "aspectratio", label: "Options.AspectRatio") {
                    Picker("Options.AspectRatio", selection: $state.cropAspect) {
                        ForEach(CropAspect.allCases) { aspect in
                            Text(aspect.label).tag(aspect)
                        }
                    }
                }
                GlassIconButton(symbol: "rotate.left", label: "Canvas.RotateLeft") {
                    state.rotateCanvas(clockwise: false)
                }
                GlassIconButton(symbol: "rotate.right", label: "Canvas.RotateRight") {
                    state.rotateCanvas(clockwise: true)
                }
                GlassIconButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Canvas.FlipHorizontal") {
                    state.flipCanvas(horizontal: true)
                }
            }
            GlassGroup {
                GlassIconButton(symbol: "xmark", label: "Options.CropReset") {
                    state.resetCrop()
                }
                GlassIconButton(symbol: "checkmark", label: "Options.CropApply", isOn: true) {
                    state.applyCrop()
                }
                .disabled(state.cropRect?.integral == state.composition.canvasRect)
                .accessibilityIdentifier("applyCrop")
            }
        }
    }

    // MARK: - Adding

    private var textOptions: some View {
        GlassGroup {
            ColorWell(state: state)
            if state.activeLayer?.isText == true {
                Button("Options.EditText") { state.presentedPanel = .text }
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .buttonStyle(.plain)
            } else {
                Text("Options.TapToAddText")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
        }
    }

    private var shapeOptions: some View {
        Group {
            GlassGroup {
                ForEach(ShapeSpec.Kind.allCases) { kind in
                    GlassIconButton(symbol: kind.symbolName, title: kind.label, isOn: state.shapeKind == kind) {
                        state.shapeKind = kind
                    }
                    .accessibilityIdentifier("shapeKind.\(kind.rawValue)")
                }
            }
            GlassGroup {
                ColorWell(state: state)
                if state.shapeKind.canFill {
                    GlassIconButton(
                        symbol: state.shapeIsFilled ? "square.fill" : "square", label: "Options.ShapeFilled",
                        isOn: state.shapeIsFilled
                    ) {
                        state.shapeIsFilled.toggle()
                    }
                }
                if !state.shapeIsFilled || !state.shapeKind.canFill {
                    OptionSlider(
                        value: Binding(
                            get: { BrushSizeScale.position(for: state.shapeLineWidth) },
                            set: { state.shapeLineWidth = BrushSizeScale.size(at: $0) }
                        ),
                        label: "Options.LineWidth", valueText: "\(Int(state.shapeLineWidth.rounded())) px"
                    )
                }
            }
        }
    }
}

/// Brush sizes run from one pixel to hundreds; a slider following the
/// square root gives the small sizes, which need the most care, room.
enum BrushSizeScale {
    static func position(for size: Double) -> Double {
        let range = BrushSettings.sizeRange
        return sqrt((size - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    static func size(at position: Double) -> Double {
        let range = BrushSettings.sizeRange
        return (range.lowerBound + position * position * (range.upperBound - range.lowerBound)).rounded()
    }
}

/// A short slider with its value beside it, sized to sit in a glass bar.
struct OptionSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    let label: LocalizedStringKey
    let valueText: String

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: $value, in: range)
                .frame(width: 120)
                .accessibilityLabel(label)
                .accessibilityValue(valueText)
            Text(valueText)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 46, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }
}

/// The colour in use, which opens the system colour picker.
struct ColorWell: View {
    @Bindable var state: EditorState

    var body: some View {
        ColorPicker(
            "Options.Color",
            selection: Binding(get: { state.color.color }, set: { state.color = RGBAColor($0) }),
            supportsOpacity: false
        )
        .labelsHidden()
        .frame(width: 40, height: 40)
        .accessibilityIdentifier("colorWell")
    }
}

/// Everything about the brush or eraser that does not fit the bar.
private struct BrushSettingsButton: View {
    @Bindable var state: EditorState
    @State private var isPresented = false

    var body: some View {
        GlassIconButton(symbol: "slider.horizontal.3", label: "Options.BrushSettings", isOn: isPresented) {
            isPresented = true
        }
        .popover(isPresented: $isPresented) {
            Form {
                Section {
                    LabeledSlider(
                        label: "Options.Size",
                        value: Binding(
                            get: { BrushSizeScale.position(for: state.currentBrush.size) },
                            set: { state.currentBrush.size = BrushSizeScale.size(at: $0) }
                        ),
                        valueText: "\(Int(state.currentBrush.size.rounded())) px"
                    )
                    // The retouching brushes have a strength where others
                    // have an opacity; heal always heals fully.
                    if state.tool != .heal {
                        LabeledSlider(
                            label: state.tool.isRetouch ? "Options.Strength" : "Options.Opacity",
                            value: $state.currentBrush.opacity,
                            valueText: "\(Int((state.currentBrush.opacity * 100).rounded()))%"
                        )
                    }
                    LabeledSlider(
                        label: "Options.Softness", value: $state.currentBrush.softness,
                        valueText: "\(Int((state.currentBrush.softness * 100).rounded()))%"
                    )
                }
                if state.tool != .smudge {
                    Section {
                        Toggle("Options.PencilPressure", isOn: $state.currentBrush.usesPressure)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 320, minHeight: 340)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// Exact scale and angle for the layer being moved.
private struct TransformSettingsButton: View {
    @Bindable var state: EditorState
    @State private var isPresented = false

    var body: some View {
        GlassIconButton(symbol: "slider.horizontal.3", label: "Options.Transform", isOn: isPresented) {
            isPresented = true
        }
        .popover(isPresented: $isPresented) {
            let transform = state.activeLayer?.transform
            Form {
                Section {
                    LabeledSlider(
                        label: "Options.Scale",
                        value: Binding(
                            get: { transform?.uniformScale ?? 1 },
                            set: { value in state.updateTransform { $0.uniformScale = value } }
                        ),
                        range: 0.05...4,
                        valueText: "\(Int(((transform?.uniformScale ?? 1) * 100).rounded()))%"
                    )
                    LabeledSlider(
                        label: "Options.Rotation",
                        value: Binding(
                            get: { (transform?.rotation ?? 0) * 180 / .pi },
                            set: { value in state.updateTransform { $0.rotation = value * .pi / 180 } }
                        ),
                        range: -180...180,
                        valueText: "\(Int((((transform?.rotation ?? 0) * 180 / .pi)).rounded()))°"
                    )
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 320, minHeight: 220)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// A slider in a form, its name above and its value at the end.
struct LabeledSlider: View {
    let label: Text
    var systemImage: String?
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    let valueText: String

    init(
        label: LocalizedStringKey, systemImage: String? = nil, value: Binding<Double>,
        range: ClosedRange<Double> = 0...1, valueText: String
    ) {
        self.init(title: Text(label), systemImage: systemImage, value: value, range: range, valueText: valueText)
    }

    /// For names already looked up, such as an adjustment's.
    init(
        title: Text, systemImage: String? = nil, value: Binding<Double>,
        range: ClosedRange<Double> = 0...1, valueText: String
    ) {
        label = title
        self.systemImage = systemImage
        _value = value
        self.range = range
        self.valueText = valueText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let systemImage {
                    Label { label } icon: { Image(systemName: systemImage) }
                } else {
                    label
                }
                Spacer()
                Text(valueText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .accessibilityLabel(label)
                .accessibilityValue(valueText)
        }
    }
}

/// What can be done with the selection.
struct SelectionMenu: View {
    @Bindable var state: EditorState

    var body: some View {
        GlassMenuButton(symbol: "ellipsis", label: "Options.SelectionActions") {
            SelectionMenuItems(state: state)
        }
        .accessibilityIdentifier("selectionMenu")
    }
}

struct SelectionMenuItems: View {
    @Bindable var state: EditorState

    var body: some View {
        let hasSelection = state.selection != nil
        Section {
            Button("Select.All", systemImage: "selection.pin.in.out") { state.selectAll() }
            Button("Select.Deselect", systemImage: "xmark.square") { state.deselect() }
                .disabled(!hasSelection)
            Button("Select.Invert", systemImage: "square.on.square.intersection.dashed") { state.invertSelection() }
                .disabled(!hasSelection)
        }
        Section {
            Button("Select.CopyToLayer", systemImage: "square.on.square") { state.copySelectionToNewLayer(cut: false) }
            Button("Select.CutToLayer", systemImage: "scissors") { state.copySelectionToNewLayer(cut: true) }
            Button("Select.Fill", systemImage: "drop.fill") { state.fillSelection() }
            Button("Select.Clear", systemImage: "trash", role: .destructive) { state.clearSelection() }
        }
        .disabled(!hasSelection)
        Section {
            Button("Select.CropToSelection", systemImage: "crop") { state.cropToSelection() }
                .disabled(!hasSelection)
        }
    }
}
