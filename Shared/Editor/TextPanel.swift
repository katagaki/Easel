import SwiftUI

/// The words and setting of the active text layer, applied as they change.
struct TextPanel: View {
    @Bindable var state: EditorState
    @FocusState private var isEditing: Bool

    var body: some View {
        Form {
            if let text = state.activeLayer?.text {
                Section {
                    TextField("Text.Placeholder", text: binding(\.string), axis: .vertical)
                        .lineLimit(1...6)
                        .focused($isEditing)
                        .accessibilityIdentifier("textContent")
                }
                Section {
                    Picker("Text.Design", selection: binding(\.design)) {
                        ForEach(TextContent.Design.allCases) { design in
                            Text(design.label).tag(design)
                        }
                    }
                    HStack {
                        Toggle("Text.Bold", systemImage: "bold", isOn: binding(\.isBold))
                        Toggle("Text.Italic", systemImage: "italic", isOn: binding(\.isItalic))
                    }
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
                    Picker("Text.Alignment", selection: binding(\.alignment)) {
                        ForEach(TextContent.Alignment.allCases) { alignment in
                            Label(alignment.label, systemImage: alignment.symbolName).tag(alignment)
                        }
                    }
                    .pickerStyle(.segmented)
                    LabeledSlider(
                        label: "Text.Size",
                        value: Binding(
                            get: { BrushSizeScale.position(for: min(text.fontSize, BrushSettings.sizeRange.upperBound)) },
                            set: { value in state.updateText { $0.fontSize = max(4, BrushSizeScale.size(at: value)) } }
                        ),
                        valueText: "\(Int(text.fontSize.rounded())) px"
                    )
                    ColorPicker(
                        "Text.Color",
                        selection: Binding(
                            get: { text.color.color },
                            set: { value in state.updateText { $0.color = RGBAColor(value) } }
                        )
                    )
                }
            } else {
                ContentUnavailableView("Text.NoTextLayer", systemImage: "textformat", description: Text("Text.NoTextLayer.Detail"))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // A new text layer starts with placeholder words, which give way
            // to whatever is typed.
            if state.activeLayer?.text?.string == String(localized: "Text.Placeholder") {
                state.updateText { $0.string = "" }
                isEditing = true
            }
        }
        .onDisappear {
            // Nothing typed: the layer it would have been is not kept.
            if let layer = state.activeLayer, layer.text?.string.isEmpty == true {
                state.deleteLayer(layer.id)
            }
        }
        .panelActions(confirm: { state.presentedPanel = nil })
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TextContent, Value>) -> Binding<Value> where Value: Equatable {
        Binding(
            get: { state.activeLayer?.text?[keyPath: keyPath] ?? TextContent(string: "", fontSize: 1, color: .black)[keyPath: keyPath] },
            set: { value in state.updateText { $0[keyPath: keyPath] = value } }
        )
    }
}
