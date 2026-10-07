import SwiftUI

/// The active layer's filters: a chain run top to bottom over its pixels,
/// every link of which stays editable. Filters can be turned off, dragged
/// into a different order, swiped away, or painted in for good.
struct LayerFiltersPanel: View {
    @Bindable var state: EditorState

    var body: some View {
        Group {
            if let layer = state.activeLayer {
                if layer.filters.isEmpty {
                    ContentUnavailableView {
                        Label("LayerFilters.Empty", systemImage: "camera.filters")
                    } description: {
                        Text("LayerFilters.Empty.Detail")
                    } actions: {
                        AddFilterMenu(state: state) {
                            Label("LayerFilters.Add", systemImage: "plus")
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("addFilterEmpty")
                    }
                } else {
                    filterList(layer)
                }
            } else {
                ContentUnavailableView("Error.NoLayer", systemImage: "square.3.layers.3d")
            }
        }
        .panelActions(confirm: { state.presentedPanel = nil })
    }

    private func filterList(_ layer: Layer) -> some View {
        List {
            Section {
                ForEach(Array(layer.filters.enumerated()), id: \.element.id) { index, filter in
                    FilterRow(
                        filter: filter, state: state,
                        canMoveUp: index > 0, canMoveDown: index < layer.filters.count - 1
                    )
                }
                // No swipe to delete: a slider dragged along its track would
                // set it off. Removing is in each filter's menu.
                .onMove { state.moveFilters(from: $0, to: $1) }
            } footer: {
                Text("LayerFilters.Footer")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // At the top, where a half-height sheet still shows them.
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                AddFilterMenu(state: state) {
                    Label("LayerFilters.Add", systemImage: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .contentShape(.capsule)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityIdentifier("addFilter")
                Spacer()
                GlassGroup {
                    GlassMenuButton(symbol: "ellipsis", label: "Layers.More") {
                        Button("LayerFilters.ApplyAll", systemImage: "square.and.arrow.down.on.square") {
                            state.applyFilters(of: layer.id)
                        }
                        .disabled(!layer.hasActiveFilters || layer.isLocked)
                        Button("LayerFilters.RemoveAll", systemImage: "trash", role: .destructive) {
                            state.updateActiveLayer { $0.filters = [] }
                        }
                    }
                    .accessibilityIdentifier("filtersMore")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
    }
}

/// One filter: what it is, whether it is on, and its settings.
private struct FilterRow: View {
    let filter: LayerFilter
    let state: EditorState
    let canMoveUp: Bool
    let canMoveDown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: filter.kind.symbolName)
                    .foregroundStyle(filter.isEnabled ? Color.accentColor : .secondary)
                    .frame(width: 24)
                Text(verbatim: filter.kind.label)
                    .font(.headline)
                Spacer()
                Menu {
                    menuItems
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Layers.More")
                .accessibilityIdentifier("filterMenu.\(filter.kind.rawValue)")
                // An eye, as for layers: a switch in a reorderable row loses
                // its taps to the row.
                Button {
                    state.updateFilter(filter.id) { $0.isEnabled.toggle() }
                } label: {
                    Image(systemName: filter.isEnabled ? "eye" : "eye.slash")
                        .foregroundStyle(filter.isEnabled ? Color.primary : Color.secondary)
                        .frame(width: 36, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(filter.isEnabled ? "LayerFilters.Hide" : "LayerFilters.Show")
                .accessibilityIdentifier("filterEnabled.\(filter.kind.rawValue)")
            }
            Group {
                LabeledSlider(
                    label: "LayerFilters.Amount",
                    value: binding(\.amount),
                    range: filter.kind.amountRange,
                    valueText: "\(Int((filter.amount * 100).rounded()))"
                )
                .accessibilityIdentifier("filterAmount.\(filter.kind.rawValue)")
                if filter.kind.hasAngle {
                    LabeledSlider(
                        label: "LayerFilters.Angle", value: binding(\.angle), range: -180...180,
                        valueText: "\(Int(filter.angle.rounded()))°"
                    )
                }
                if filter.kind.hasCenter {
                    LabeledSlider(
                        label: "LayerFilters.CenterX", value: binding(\.centerX),
                        valueText: "\(Int((filter.centerX * 100).rounded()))%"
                    )
                    LabeledSlider(
                        label: "LayerFilters.CenterY", value: binding(\.centerY),
                        valueText: "\(Int((filter.centerY * 100).rounded()))%"
                    )
                }
            }
            .disabled(!filter.isEnabled)
            .opacity(filter.isEnabled ? 1 : 0.5)
        }
        .padding(.vertical, 4)
        .contextMenu { menuItems }
    }

    @ViewBuilder
    private var menuItems: some View {
        Section {
            Button("Layers.MoveUp", systemImage: "arrow.up") { move(by: -1) }
                .disabled(!canMoveUp)
            Button("Layers.MoveDown", systemImage: "arrow.down") { move(by: 1) }
                .disabled(!canMoveDown)
        }
        Button("LayerFilters.Remove", systemImage: "trash", role: .destructive) {
            state.removeFilter(filter.id)
        }
    }

    private func move(by offset: Int) {
        guard let index = state.activeLayer?.filters.firstIndex(where: { $0.id == filter.id }) else { return }
        // `move(fromOffsets:toOffset:)` counts the destination before removal.
        state.moveFilters(from: [index], to: offset > 0 ? index + 2 : index - 1)
    }

    private func binding(_ keyPath: WritableKeyPath<LayerFilter, Double>) -> Binding<Double> {
        Binding(
            get: { filter[keyPath: keyPath] },
            set: { value in state.updateFilter(filter.id) { $0[keyPath: keyPath] = value } }
        )
    }
}

/// The kinds of filter that can be added, grouped as tone and colour, then
/// blurs and mosaic.
struct AddFilterMenu<Label: View>: View {
    let state: EditorState
    @ViewBuilder var label: Label

    var body: some View {
        Menu {
            ForEach(Array(LayerFilter.Kind.groups.enumerated()), id: \.offset) { _, kinds in
                Section {
                    ForEach(kinds) { kind in
                        Button {
                            state.addFilter(kind)
                        } label: {
                            SwiftUI.Label {
                                Text(verbatim: kind.label)
                            } icon: {
                                Image(systemName: kind.symbolName)
                            }
                        }
                        .accessibilityIdentifier("addFilter.\(kind.rawValue)")
                    }
                }
            }
        } label: {
            label
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}
