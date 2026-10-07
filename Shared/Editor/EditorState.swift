import SwiftUI

/// Everything about an editing session that is not part of the picture
/// itself: the tool in hand, its settings, the selection, the view onto the
/// canvas, and edits still being worked out.
@MainActor
@Observable
final class EditorState {
    // MARK: Tools

    var tool: Tool = .brush {
        didSet { toolDidChange(from: oldValue) }
    }
    var activeLayerID: Layer.ID? {
        didSet {
            if activeLayerID != oldValue {
                isEditingMask = false
                activeGroupID = nil
                if tool == .transform { cancelTransform() }
            }
        }
    }
    /// A group picked in the Layers panel, which the Move tool moves whole.
    var activeGroupID: UUID?
    /// Whether painting goes into the active layer's mask rather than its
    /// pixels: the brush hides, the eraser reveals.
    var isEditingMask = false
    var brush = BrushSettings(size: 24, color: .black)
    var eraser = BrushSettings(size: 60, softness: 0.3)
    /// For the retouching brushes, opacity is strength: how far a smear
    /// carries, how blurred or how coarse the tiles, how fully a spot heals.
    var smudgeBrush = BrushSettings(size: 60, opacity: 0.7, softness: 0.5, usesPressure: false)
    var liquifyBrush = BrushSettings(size: 120, opacity: 0.6, softness: 0.5, usesPressure: false)
    var blurBrush = BrushSettings(size: 80, opacity: 0.5, softness: 0.5, usesPressure: false)
    var mosaicBrush = BrushSettings(size: 80, opacity: 0.6, usesPressure: false)
    var healBrush = BrushSettings(size: 40, softness: 0.3, usesPressure: false)
    var cloneBrush = BrushSettings(size: 60, softness: 0.4, usesPressure: false)
    /// Where the clone stamp copies from, in canvas pixels. It moves with
    /// the brush, so after a stroke it sits as far from where the stroke
    /// ended as it was from where it began.
    var cloneSource: CGPoint?
    /// How far the copy is from the brush. Set by the first stroke after the
    /// source is picked and kept for later ones, so separate strokes go on
    /// copying the same picture.
    var cloneOffset: CGVector?
    /// Whether the next tap picks the clone stamp's source.
    var isPickingCloneSource = false
    var fillTolerance = 0.12
    var gradientOpacity = 1.0
    var shapeKind: ShapeSpec.Kind = .rectangle
    var shapeIsFilled = false
    var shapeLineWidth = 12.0
    var selectionKind: SelectionKind = .rectangle
    /// How different a colour may be and still be picked by magic select.
    var selectionTolerance = 0.15
    /// The picture's edges, for magnetic select to cling to; worked out
    /// when a magnetic drag starts.
    @ObservationIgnored var edgeMap: EdgeMap?
    @ObservationIgnored private var edgeMapSource: Composition?
    var cropAspect: CropAspect = .free {
        didSet { constrainCropRect() }
    }

    /// The colour brushes, fills, shapes and new text use.
    var color: RGBAColor {
        get { brush.color }
        set { brush.color = newValue.withAlpha(1) }
    }

    // MARK: Selection and drafts

    var selection: Selection?
    /// A stroke still under the finger.
    var activeStroke: Stroke?
    /// Strokes lifted but not yet painted into their layer, drawn over it
    /// in the meantime so nothing flickers.
    var pendingStrokes: [PendingStroke] = []
    /// The blur or mosaic the blur and mosaic brushes reveal.
    var retouchEffect: RetouchPreparation?
    /// A smear being made.
    var smudge: SmudgeSession?
    /// The path the pen is adding points to.
    var penPath: VectorPathRef?
    /// Whether a new pen path joins the active vector layer rather than
    /// starting a layer of its own.
    var penAddsToLayer = true
    /// The point picked out for editing.
    var selectedNode: VectorNodeRef?
    /// Points picked alongside it, which move and go with it.
    var additionalNodes: [VectorNodeRef] = []
    /// Whether tapping a point adds it to those picked.
    var isSelectingMultiplePoints = false
    @ObservationIgnored var vectorDrag: VectorDrag?
    var draftSelection: Selection?
    var draftShape: ShapeSpec?
    var draftGradient: (start: CGPoint, end: CGPoint)?
    /// The crop tool's frame, in canvas pixels; nil until the tool is picked.
    var cropRect: CGRect?
    /// The layer the Transform tool is bending, and how.
    var transformDraft: TransformDraft?
    var transformMode: TransformMode = .distort
    /// The bent layer as it will look, canvas-aligned and shrunk.
    var transformPreview: LayerPreview?
    @ObservationIgnored var transformDrag: TransformDrag?
    @ObservationIgnored var transformPreviewTask: Task<Void, Never>?

    // MARK: View

    /// 1 shows the whole canvas fitted to the screen.
    var zoom: Double = 1
    var pan: CGSize = .zero
    static let zoomRange: ClosedRange<Double> = 0.25...32
    /// The size of the area the canvas is drawn in.
    var viewportSize: CGSize = .zero
    /// Room kept clear around the canvas for the tool bars over it.
    var canvasInsets = EdgeInsets()

    // MARK: Panels and progress

    var presentedPanel: EditorPanel?
    /// On iPad, whether the inspector beside the canvas is open.
    var isInspectorPresented = true
    /// A stand-in for one layer's pixels while an adjustment or filter is
    /// being tried; shown until it is applied or abandoned.
    var layerPreview: LayerPreview?
    var isImportingFiles = false
    var errorMessage: String?
    /// How many edits are being worked on off the main thread.
    private(set) var runningJobs = 0
    var isBusy: Bool { runningJobs > 0 }

    /// The picture being edited. Kept here as well as in the host's binding:
    /// a document's binding hands back its old value until the next update,
    /// so an edit that reads straight after another would undo it.
    private(set) var composition: Composition = .blank()
    /// Hands each edit on to the host, which keeps or saves it.
    @ObservationIgnored private var publish: (Composition) -> Void = { _ in /* Replaced on attach. */ }
    /// What was handed to the host lately, newest last. A document reports
    /// its value back some time after it is set, so during a drag it can
    /// report a step the editor has already moved past — or, after an undo,
    /// one the undo took away. Those are echoes, not changes.
    @ObservationIgnored private var recentlyPublished: [Composition] = []
    @ObservationIgnored private var hasSizedBrushes = false
    /// Told of every change made here, which is what undo records. Changes
    /// the host makes — such as a document reading itself back after its
    /// first save — are not edits and are not undoable.
    @ObservationIgnored var edited: (_ old: Composition, _ new: Composition) -> Void = { _, _ in
        // Replaced by the editor view.
    }
    /// Where edits worked out off the main thread wait their turn, so each
    /// starts from the result of the one before.
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var moveOrigin: MoveOrigin?
    @ObservationIgnored private var groupMoveOrigin: (start: CGPoint, layers: [(Layer.ID, LayerTransform)])?
    @ObservationIgnored private var cropDrag: CropDrag?
    /// The adjustment or filter preview being worked out, which a newer one
    /// replaces.
    @ObservationIgnored var previewTask: Task<Void, Never>?
    /// For each layer with filters, its newest filtered pixels and what they
    /// were worked out from. Kept on screen while newer ones are worked out,
    /// and observed, so the canvas redraws as each arrives.
    private var filteredDisplay: [Layer.ID: (key: FilterCache.Key, image: CGImage)] = [:]
    /// The filtering each layer is waiting for. Only the newest is kept: a
    /// slider being dragged asks far faster than filters can run.
    @ObservationIgnored private var wantedFilters: [Layer.ID: (key: FilterCache.Key, source: LayerImage)] = [:]
    @ObservationIgnored private var filteringLayers: Set<Layer.ID> = []

    struct PendingStroke: Identifiable {
        let id = UUID()
        var layerID: Layer.ID
        var stroke: Stroke
        /// Painted into the layer's mask rather than its pixels.
        var isMask = false
    }

    struct LayerPreview {
        var layerID: Layer.ID
        var image: CGImage
    }

    private struct MoveOrigin {
        var layerID: Layer.ID
        var start: CGPoint
        var transform: LayerTransform
    }

    private struct CropDrag {
        /// Which edges move: -1 the minimum edge, 1 the maximum, 0 neither.
        var horizontal: Int
        var vertical: Int
        var start: CGPoint
        var rect: CGRect
    }

    init() {}

    // MARK: - Document access

    func read() -> Composition { composition }

    /// Replaces the picture and passes it to the host.
    func write(_ composition: Composition) {
        let previous = self.composition
        self.composition = composition
        recentlyPublished.append(composition)
        if recentlyPublished.count > 64 { recentlyPublished.removeFirst(recentlyPublished.count - 64) }
        publish(composition)
        edited(previous, composition)
    }

    func attach(to composition: Composition, publish: @escaping (Composition) -> Void) {
        self.publish = publish
        if !hasSizedBrushes {
            sizeBrushes(for: composition.size)
            hasSizedBrushes = true
        }
        self.composition = composition
        if activeLayerID.flatMap({ composition.index(of: $0) }) == nil {
            activeLayerID = composition.layers.last?.id
        }
    }

    /// The brush sizes above suit a canvas about a thousand pixels across;
    /// a 12-megapixel photo needs them several times larger to make the
    /// same mark on screen.
    private func sizeBrushes(for canvasSize: CGSize) {
        resizeBrushes(by: max(0.5, max(canvasSize.width, canvasSize.height) / 1024))
    }

    /// Scales every brush, as when a picture replaces the canvas it was
    /// sized for.
    func resizeBrushes(by factor: Double) {
        func scaled(_ settings: inout BrushSettings) {
            settings.size = min(BrushSettings.sizeRange.upperBound, (settings.size * factor).rounded())
        }
        scaled(&brush)
        scaled(&eraser)
        scaled(&smudgeBrush)
        scaled(&liquifyBrush)
        scaled(&blurBrush)
        scaled(&mosaicBrush)
        scaled(&healBrush)
        scaled(&cloneBrush)
        shapeLineWidth = (shapeLineWidth * factor).rounded()
    }

    /// Takes in a change the host made, such as an undo, or the host catching
    /// up with an edit made here.
    func sync(_ composition: Composition) {
        guard composition != self.composition else { return }
        if recentlyPublished.contains(composition) {
            // Behind the editor: either a late report of an earlier step, or
            // the system's own undo stepping the document back. Either way
            // the editor's picture is the real one, and the file must say so.
            publish(self.composition)
            return
        }
        self.composition = composition
        if activeLayerID.flatMap({ composition.index(of: $0) }) == nil {
            activeLayerID = composition.layers.last?.id
        }
    }

    /// Changes the picture.
    func update(_ change: (inout Composition) -> Void) {
        var composition = read()
        change(&composition)
        write(composition)
    }

    var activeLayer: Layer? {
        activeLayerID.flatMap { read()[$0] }
    }

    func updateActiveLayer(_ change: (inout Layer) -> Void) {
        guard let id = activeLayerID else { return }
        update { composition in
            guard var layer = composition[id] else { return }
            change(&layer)
            composition[id] = layer
        }
    }

    /// After an undo or redo, lets go of whatever the change took away.
    func showRestored(_ composition: Composition) {
        if activeLayerID.flatMap({ composition.index(of: $0) }) == nil {
            activeLayerID = composition.layers.last?.id
        }
        pendingStrokes.removeAll { composition.index(of: $0.layerID) == nil }
        if let preview = layerPreview, composition.index(of: preview.layerID) == nil { layerPreview = nil }
        if tool == .crop { cropRect = composition.canvasRect }
        if tool == .transform { cancelTransform() }
        if let selection, !composition.canvasRect.intersects(selection.bounds(in: composition.size)) {
            self.selection = nil
        }
    }

    // MARK: - Filtered layers

    /// Longest side of the copy a filtered layer is shown from: plenty for a
    /// screen, and small enough for filters to follow a slider.
    nonisolated static let filterDisplaySize = 3000

    /// What to show for a layer: its own pixels, or — when it has filters —
    /// the newest filtered copy ready, asking for a fresher one if needed.
    func displayImage(for layer: Layer) -> CGImage {
        guard layer.hasActiveFilters else { return layer.image.cgImage }
        let key = FilterCache.Key(layer: layer, maxPixelSize: Self.filterDisplaySize)
        let shown = filteredDisplay[layer.id]
        if let shown, shown.key == key { return shown.image }
        requestFiltering(layer.id, key: key, source: layer.image)
        return shown?.image ?? layer.image.cgImage
    }

    private func requestFiltering(_ layerID: Layer.ID, key: FilterCache.Key, source: LayerImage) {
        // Asked for during a canvas update: only note it here, and start the
        // work once the update is over.
        wantedFilters[layerID] = (key, source)
        guard filteringLayers.insert(layerID).inserted else { return }
        Task { @MainActor in
            while let wanted = wantedFilters.removeValue(forKey: layerID) {
                let image = await Task.detached(priority: .userInitiated) {
                    FilterCache.shared.image(for: wanted.key, source: wanted.source)
                }.value
                filteredDisplay[layerID] = (wanted.key, image)
            }
            filteringLayers.remove(layerID)
        }
    }

    // MARK: - Viewport

    /// Where the canvas sits on screen.
    var viewport: CanvasViewport {
        CanvasViewport(
            canvasSize: read().size, viewportSize: viewportSize, insets: canvasInsets, zoom: zoom, pan: pan
        )
    }

    func zoom(by factor: Double, around anchor: CGPoint) {
        let before = viewport
        let canvasPoint = before.canvasPoint(anchor)
        zoom = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        // Keep the canvas point under the fingers where it was.
        let after = viewport
        let drifted = after.screenPoint(canvasPoint)
        pan.width += anchor.x - drifted.x
        pan.height += anchor.y - drifted.y
    }

    func pan(by translation: CGSize) {
        pan.width += translation.width
        pan.height += translation.height
    }

    func fitCanvas() {
        zoom = 1
        pan = .zero
    }

    /// Shows canvas pixels one for one with screen pixels.
    func zoomToActualSize(displayScale: Double) {
        let fit = viewport.fitScale
        guard fit > 0 else { return }
        zoom = min(max(1 / (fit * displayScale), Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        pan = .zero
    }

    // MARK: - Tools

    private func toolDidChange(from old: Tool) {
        guard tool != old else { return }
        penPath = nil
        activeStroke = nil
        smudge = nil
        draftShape = nil
        draftSelection = nil
        draftGradient = nil
        if tool == .crop {
            cropRect = read().canvasRect
            constrainCropRect()
        } else {
            cropRect = nil
        }
        if tool == .transform {
            beginTransformDraft()
        } else if old == .transform {
            transformPreviewTask?.cancel()
            transformDraft = nil
            transformPreview = nil
        }
    }

    /// The settings the brush, eraser or retouching brush in hand uses.
    var currentBrush: BrushSettings {
        get {
            switch tool {
            case .eraser: return eraser
            case .smudge: return smudgeBrush
            case .liquify: return liquifyBrush
            case .blur: return blurBrush
            case .mosaic: return mosaicBrush
            case .heal: return healBrush
            case .clone: return cloneBrush
            default: return brush
            }
        }
        set {
            switch tool {
            case .eraser: eraser = newValue
            case .smudge: smudgeBrush = newValue
            case .liquify: liquifyBrush = newValue
            case .blur: blurBrush = newValue
            case .mosaic: mosaicBrush = newValue
            case .heal: healBrush = newValue
            case .clone: cloneBrush = newValue
            default: brush = newValue
            }
        }
    }

    /// What a stroke made with the tool in hand does.
    var strokeKind: Stroke.Kind {
        switch tool {
        case .eraser: return .erase
        case .blur: return .blur
        case .mosaic: return .mosaic
        case .heal: return .heal
        case .clone: return .clone(offset: cloneOffset ?? .zero)
        default: return .paint
        }
    }

    /// Why the active layer cannot be painted on, if it cannot.
    func paintingBlocker() -> String? {
        guard let layer = activeLayer else { return String(localized: "Error.NoLayer") }
        if composition.isLocked(layer) { return String(localized: "Error.LayerLocked") }
        if editsMask, ![Tool.brush, .eraser, .gradient].contains(tool) {
            return String(localized: "Error.MaskTool")
        }
        if !layer.isVisible || composition.ancestors(of: layer.groupID).contains(where: { !$0.isVisible }) {
            return String(localized: "Error.LayerHidden")
        }
        return nil
    }

    /// Whether painting goes into a mask right now.
    var editsMask: Bool { isEditingMask && activeLayer?.mask != nil }

    /// A mask is painted where it lines up with the canvas, so the stroke
    /// shown under the finger matches what is painted. Lines it up first.
    private func alignForMaskPainting() {
        guard let layer = activeLayer, !layer.isAligned(to: composition.size) else { return }
        let size = composition.size
        update { $0[layer.id] = layer.aligned(in: size) }
    }

    /// Selection outline for clipping, in canvas pixels.
    var selectionPath: CGPath? {
        selection.map { $0.path(in: read().size) }
    }

    // MARK: - Gestures

    /// A finger or pencil came down on the canvas.
    func toolBegan(at point: CGPoint, pressure: Double) {
        // An adjustment being tried stands in for the layer; painting under
        // it would be hidden, then lost when it is applied.
        guard layerPreview == nil else { return }
        switch tool {
        case .brush, .eraser, .blur, .mosaic, .heal, .clone:
            guard paintingBlocker() == nil else { return }
            if tool == .clone {
                // Until there is a source, a touch only picks one.
                guard let source = cloneSource, !isPickingCloneSource else { return }
                if cloneOffset == nil { cloneOffset = CGVector(dx: source.x - point.x, dy: source.y - point.y) }
            }
            if editsMask {
                alignForMaskPainting()
                // On a mask the brush hides and the eraser reveals.
                var settings = currentBrush
                settings.color = .white
                activeStroke = Stroke(
                    points: [StrokePoint(location: point, pressure: pressure)],
                    settings: settings, kind: tool == .brush ? .erase : .paint, clip: selection
                )
                return
            }
            if tool == .blur || tool == .mosaic || tool == .clone { prepareRetouchEffect() }
            activeStroke = Stroke(
                points: [StrokePoint(location: point, pressure: pressure)],
                settings: currentBrush, kind: strokeKind, clip: selection
            )
        case .smudge, .liquify:
            guard paintingBlocker() == nil else { return }
            beginSmudge(at: point)
        case .move:
            if let groupID = activeGroupID, let group = composition.group(groupID) {
                guard !group.isLocked else { return }
                let members = composition.layers(in: groupID).filter { !composition.isLocked($0) }
                groupMoveOrigin = (point, members.map { ($0.id, $0.transform) })
                return
            }
            guard let layer = activeLayer, !composition.isLocked(layer) else { return }
            moveOrigin = MoveOrigin(layerID: layer.id, start: point, transform: layer.transform)
        case .select:
            guard selectionKind.isDrawn else { return }
            if selectionKind == .magnetic { prepareEdgeMap() }
            draftSelection = Selection(shape: shape(for: selectionKind, from: point, to: point))
        case .pen:
            penBegan(at: point)
        case .nodes:
            nodesBegan(at: point)
        case .transform:
            transformBegan(at: point)
        case .shape:
            draftShape = ShapeSpec(
                kind: shapeKind, start: point, end: point, isFilled: shapeIsFilled,
                lineWidth: shapeLineWidth, color: color
            )
        case .gradient:
            guard paintingBlocker() == nil else { return }
            draftGradient = (point, point)
        case .crop:
            beginCropDrag(at: point)
        case .eyedropper:
            sampleColor(at: point)
        case .fill, .text:
            break
        }
    }

    func toolMoved(to points: [StrokePoint]) {
        guard let last = points.last else { return }
        switch tool {
        case .brush, .eraser, .blur, .mosaic, .heal, .clone:
            activeStroke?.points.append(contentsOf: points)
        case .smudge, .liquify:
            continueSmudge(to: points.map(\.location))
        case .move:
            if let group = groupMoveOrigin {
                let dx = last.location.x - group.start.x, dy = last.location.y - group.start.y
                update { composition in
                    for (id, transform) in group.layers {
                        var moved = transform
                        moved.position.x += dx
                        moved.position.y += dy
                        composition[id]?.transform = moved
                    }
                }
                return
            }
            guard let origin = moveOrigin else { return }
            var transform = origin.transform
            transform.position.x += last.location.x - origin.start.x
            transform.position.y += last.location.y - origin.start.y
            update { $0[origin.layerID]?.transform = transform }
        case .select:
            guard let draft = draftSelection else { return }
            switch draft.shape {
            case .lasso(let existing) where selectionKind == .magnetic:
                draftSelection = Selection(shape: .lasso(existing + magneticPoints(points.map(\.location), after: existing.last)))
            case .lasso(let existing):
                draftSelection = Selection(shape: .lasso(existing + points.map(\.location)))
            case .rectangle(let rect), .ellipse(let rect):
                draftSelection = Selection(shape: shape(for: selectionKind, from: rect.origin, to: last.location))
            case .mask:
                break
            }
        case .pen:
            penMoved(to: last.location)
        case .nodes:
            nodesMoved(to: last.location)
        case .transform:
            transformMoved(to: last.location)
        case .shape:
            draftShape?.end = last.location
        case .gradient:
            draftGradient?.end = last.location
        case .crop:
            continueCropDrag(to: last.location)
        case .eyedropper:
            sampleColor(at: last.location)
        case .fill, .text:
            break
        }
    }

    /// The finger lifted. `isTap` when it barely moved.
    func toolEnded(isTap: Bool, at point: CGPoint) {
        switch tool {
        case .smudge, .liquify:
            if let blocker = paintingBlocker(), isTap {
                errorMessage = blocker
                return
            }
            finishSmudge()
        case .brush, .eraser, .blur, .mosaic, .heal, .clone:
            if let blocker = paintingBlocker(), isTap {
                errorMessage = blocker
                return
            }
            if tool == .clone, cloneSource == nil || isPickingCloneSource {
                pickCloneSource(at: point)
                return
            }
            guard let stroke = activeStroke, let layerID = activeLayerID else { return }
            activeStroke = nil
            if case .clone(let offset) = stroke.kind, let last = stroke.points.last?.location {
                cloneSource = CGPoint(x: last.x + offset.dx, y: last.y + offset.dy)
            }
            if editsMask {
                commitMask(stroke, to: layerID)
            } else {
                commit(stroke, to: layerID)
            }
        case .move:
            moveOrigin = nil
            groupMoveOrigin = nil
            if isTap { selectLayer(at: point) }
        case .select:
            defer { draftSelection = nil }
            if !selectionKind.isDrawn {
                guard isTap else { return }
                if selectionKind == .object { selectObject(at: point) } else { magicSelect(at: point) }
            } else if isTap {
                selection = nil
            } else if let draft = draftSelection, draft.isMeaningful {
                selection = draft
            }
        case .pen:
            vectorDrag = nil
        case .nodes:
            nodesEnded(isTap: isTap, at: point)
        case .transform:
            transformEnded()
        case .shape:
            defer { draftShape = nil }
            guard let spec = draftShape, spec.isMeaningful else { return }
            addShapeLayer(spec)
        case .gradient:
            defer { draftGradient = nil }
            if isTap, let blocker = paintingBlocker() {
                errorMessage = blocker
                return
            }
            guard let draft = draftGradient, hypot(draft.end.x - draft.start.x, draft.end.y - draft.start.y) > 2 else {
                return
            }
            applyGradient(from: draft.start, to: draft.end)
        case .crop:
            cropDrag = nil
        case .fill:
            guard isTap else { return }
            floodFill(at: point)
        case .text:
            guard isTap else { return }
            placeText(at: point)
        case .eyedropper:
            break
        }
    }

    /// A second finger came down, or the system took the touch: nothing the
    /// gesture had started is kept.
    func toolCancelled() {
        activeStroke = nil
        smudge = nil
        draftSelection = nil
        draftShape = nil
        draftGradient = nil
        cropDrag = nil
        if let drag = transformDrag, var draft = transformDraft {
            for handle in drag.handles { draft.points[handle.index] = handle.origin }
            transformDraft = draft
            transformDrag = nil
            updateTransformPreview()
        }
        if let origin = moveOrigin {
            update { $0[origin.layerID]?.transform = origin.transform }
            moveOrigin = nil
        }
        if let group = groupMoveOrigin {
            update { composition in
                for (id, transform) in group.layers { composition[id]?.transform = transform }
            }
            groupMoveOrigin = nil
        }
    }

    private func shape(for kind: SelectionKind, from start: CGPoint, to end: CGPoint) -> Selection.Shape {
        let rect = CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
        switch kind {
        case .rectangle: return .rectangle(rect)
        case .ellipse: return .ellipse(rect)
        case .lasso, .magnetic, .magic, .object: return .lasso([start])
        }
    }

    // MARK: - Magnetic select

    /// Works out the picture's edges, unless they are already known for it.
    private func prepareEdgeMap() {
        let composition = composition
        guard edgeMapSource != composition else { return }
        edgeMapSource = composition
        edgeMap = nil
        Task { @MainActor in
            let map = await Task.detached(priority: .userInitiated) { EdgeMap(composition: composition) }.value
            if edgeMapSource == composition { edgeMap = map }
        }
    }

    /// The finger's path pulled onto the nearest strong edge, with points
    /// too close together left out so the outline stays smooth.
    private func magneticPoints(_ points: [CGPoint], after previous: CGPoint?) -> [CGPoint] {
        guard let edgeMap else { return points }
        // About a fingertip's reach on screen.
        let radius = max(4, 16 / max(viewport.scale, 0.0001))
        var result: [CGPoint] = []
        var last = previous
        for point in points {
            let snapped = edgeMap.snap(point, radius: radius)
            if let last, hypot(snapped.x - last.x, snapped.y - last.y) < edgeMap.scale { continue }
            result.append(snapped)
            last = snapped
        }
        return result
    }

    // MARK: - Simple tool actions

    func sampleColor(at point: CGPoint) {
        guard let sampled = CompositionRenderer.color(at: point, in: read()) else { return }
        color = sampled
    }

    /// Picks the topmost visible layer under the point, the way tapping an
    /// object picks it.
    func selectLayer(at point: CGPoint) {
        let composition = read()
        if let hit = composition.layers.last(where: { $0.isVisible && $0.contains(point) }) {
            activeLayerID = hit.id
        }
    }

    // MARK: - Crop

    private func beginCropDrag(at point: CGPoint) {
        guard let rect = cropRect else { return }
        // Grab an edge from this far away, in canvas pixels.
        let reach = 28 / max(viewport.scale, 0.0001)
        func edge(_ value: CGFloat, _ min: CGFloat, _ max: CGFloat) -> Int {
            if abs(value - min) < reach { return -1 }
            if abs(value - max) < reach { return 1 }
            return 0
        }
        cropDrag = CropDrag(
            horizontal: edge(point.x, rect.minX, rect.maxX), vertical: edge(point.y, rect.minY, rect.maxY),
            start: point, rect: rect
        )
    }

    private func continueCropDrag(to point: CGPoint) {
        guard let drag = cropDrag else { return }
        let canvas = read().canvasRect
        let dx = point.x - drag.start.x
        let dy = point.y - drag.start.y
        var rect = drag.rect
        if drag.horizontal == 0 && drag.vertical == 0 {
            // Inside: the frame moves, kept on the canvas.
            rect.origin.x = min(max(rect.minX + dx, 0), canvas.width - rect.width)
            rect.origin.y = min(max(rect.minY + dy, 0), canvas.height - rect.height)
            cropRect = rect
            return
        }
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        let minimum: CGFloat = 16
        if drag.horizontal < 0 { minX = min(max(0, minX + dx), maxX - minimum) }
        if drag.horizontal > 0 { maxX = max(min(canvas.width, maxX + dx), minX + minimum) }
        if drag.vertical < 0 { minY = min(max(0, minY + dy), maxY - minimum) }
        if drag.vertical > 0 { maxY = max(min(canvas.height, maxY + dy), minY + minimum) }
        rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if let ratio = cropAspect.ratio(for: canvas.size) {
            rect = Self.fit(rect, to: ratio, anchoredOpposite: drag, in: canvas)
        }
        cropRect = rect
    }

    /// Bends a dragged frame to a fixed shape, keeping the corner or edge
    /// opposite the one being dragged where it was.
    private static func fit(_ rect: CGRect, to ratio: Double, anchoredOpposite drag: CropDrag, in canvas: CGRect) -> CGRect {
        var width = rect.width
        var height = rect.height
        if drag.vertical == 0 || (drag.horizontal != 0 && width / height > ratio) {
            height = width / ratio
        } else {
            width = height * ratio
        }
        let anchorX = drag.horizontal < 0 ? rect.maxX : rect.minX
        let anchorY = drag.vertical < 0 ? rect.maxY : rect.minY
        var result = CGRect(
            x: drag.horizontal < 0 ? anchorX - width : anchorX,
            y: drag.vertical < 0 ? anchorY - height : anchorY,
            width: width, height: height
        )
        if !canvas.contains(result) {
            let clipped = result.intersection(canvas)
            let scale = min(clipped.width / result.width, clipped.height / result.height)
            result.size = CGSize(width: result.width * scale, height: result.height * scale)
            result.origin.x = drag.horizontal < 0 ? anchorX - result.width : anchorX
            result.origin.y = drag.vertical < 0 ? anchorY - result.height : anchorY
        }
        return result
    }

    /// Fits the crop frame to the chosen proportions, centred where it was.
    func constrainCropRect() {
        guard let rect = cropRect else { return }
        let canvas = read().canvasRect
        guard let ratio = cropAspect.ratio(for: canvas.size) else { return }
        var size = rect.size
        if size.width / size.height > ratio {
            size.width = size.height * ratio
        } else {
            size.height = size.width / ratio
        }
        cropRect = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
            .intersection(canvas)
    }

    func applyCrop() {
        guard let rect = cropRect?.integral else { return }
        let canvas = read().canvasRect
        guard rect != canvas else { return }
        update { $0.crop(to: rect) }
        selection = selection.map {
            $0.applying(CGAffineTransform(translationX: -rect.minX, y: -rect.minY), canvasSize: rect.size)
        }
        cropRect = read().canvasRect
        cropAspect = .free
        fitCanvas()
    }

    func resetCrop() {
        cropAspect = .free
        cropRect = read().canvasRect
    }

    // MARK: - Work off the main thread

    /// Runs `work` off the main thread, after every edit queued before it,
    /// and hands its result to `apply` back on the main thread.
    func enqueue<Result: Sendable>(
        _ work: @escaping @Sendable () -> Result?,
        apply: @escaping @MainActor (Result) -> Void,
        finally: @escaping @MainActor () -> Void = {}
    ) {
        let previous = queue
        runningJobs += 1
        queue = Task { @MainActor in
            await previous?.value
            let result = await Task.detached(priority: .userInitiated) { work() }.value
            if let result { apply(result) }
            finally()
            runningJobs -= 1
        }
    }

    /// Replaces a layer's pixels with ones worked out from it, after making
    /// its pixels line up with the canvas. The layer is read when the work
    /// starts, so queued edits build on each other. Its filters stay.
    func editPixels(
        of layerID: Layer.ID, mask: Bool = false, finally: @escaping @MainActor () -> Void = {},
        _ edit: @escaping @Sendable (CGImage, CGSize) -> CGImage?
    ) {
        let previous = queue
        runningJobs += 1
        queue = Task { @MainActor in
            await previous?.value
            let composition = read()
            if let layer = composition[layerID] {
                let size = composition.size
                let result = await Task.detached(priority: .userInitiated) { () -> Layer? in
                    let aligned = layer.aligned(in: size)
                    var edited = aligned
                    if mask {
                        guard let target = aligned.mask, let image = edit(target.image.cgImage, size) else { return nil }
                        edited.mask?.image = LayerImage(image)
                    } else {
                        guard let image = edit(aligned.image.cgImage, size) else { return nil }
                        edited.image = LayerImage(image)
                    }
                    return edited
                }.value
                if let result {
                    // Whatever happened to the layer meanwhile besides its
                    // pixels — a rename, a new opacity — is kept.
                    update { composition in
                        guard var current = composition[layerID] else { return }
                        current.image = result.image
                        current.text = nil
                        current.vector = nil
                        current.transform = result.transform
                        if let mask = result.mask { current.mask?.image = mask.image }
                        composition[layerID] = current
                    }
                }
            }
            finally()
            runningJobs -= 1
        }
    }

    private func commitMask(_ stroke: Stroke, to layerID: Layer.ID) {
        let pending = PendingStroke(layerID: layerID, stroke: stroke, isMask: true)
        pendingStrokes.append(pending)
        editPixels(of: layerID, mask: true, finally: { [weak self] in
            self?.pendingStrokes.removeAll { $0.id == pending.id }
        }) { image, _ in
            Painter.paint(stroke, onto: image)
        }
    }

    private func commit(_ stroke: Stroke, to layerID: Layer.ID) {
        let pending = PendingStroke(layerID: layerID, stroke: stroke)
        pendingStrokes.append(pending)
        // The blurred or tiled layer worked out for showing the stroke, if
        // it is still for these pixels; otherwise it is made again.
        let prepared = retouchEffect
        editPixels(of: layerID, finally: { [weak self] in
            self?.pendingStrokes.removeAll { $0.id == pending.id }
        }) { image, _ in
            switch stroke.kind {
            case .paint, .erase:
                return Painter.paint(stroke, onto: image)
            case .blur, .mosaic, .clone:
                let effect = prepared.flatMap { $0.matches(stroke, source: image) ? $0.image : nil }
                    ?? RetouchEffect.image(stroke.kind, settings: stroke.settings, of: image)
                return Painter.apply(effect, onto: image, through: stroke)
            case .heal:
                return Healer.heal(image, with: stroke)
            }
        }
    }

    private func floodFill(at point: CGPoint) {
        if let blocker = paintingBlocker() {
            errorMessage = blocker
            return
        }
        guard let layerID = activeLayerID else { return }
        let color = color
        let tolerance = fillTolerance
        let selection = selection
        editPixels(of: layerID) { image, size in
            Painter.floodFill(image, at: point, with: color, tolerance: tolerance, clip: selection)
        }
    }

    private func applyGradient(from start: CGPoint, to end: CGPoint) {
        guard let layerID = activeLayerID else { return }
        // On a mask, a gradient fades the layer out from where it starts.
        let onMask = editsMask
        let color = onMask ? RGBAColor.white : color
        let opacity = gradientOpacity
        let selection = selection
        editPixels(of: layerID, mask: onMask) { image, size in
            Painter.gradient(
                from: start, to: end, color: color, opacity: opacity, clip: selection,
                erasing: onMask, onto: image
            )
        }
    }
}

/// The mapping between canvas pixels and the points of the view showing them.
struct CanvasViewport: Equatable {
    var canvasSize: CGSize
    var viewportSize: CGSize
    var insets: EdgeInsets
    var zoom: Double
    var pan: CGSize

    /// The scale at which the canvas just fits the clear area.
    var fitScale: Double {
        let width = viewportSize.width - insets.leading - insets.trailing - 32
        let height = viewportSize.height - insets.top - insets.bottom - 32
        guard canvasSize.width > 0, canvasSize.height > 0, width > 0, height > 0 else { return 1 }
        return min(width / canvasSize.width, height / canvasSize.height)
    }

    /// Points per canvas pixel.
    var scale: Double { fitScale * zoom }

    /// The middle of the clear area, where a fitted canvas is centred.
    private var restingCenter: CGPoint {
        CGPoint(
            x: insets.leading + (viewportSize.width - insets.leading - insets.trailing) / 2,
            y: insets.top + (viewportSize.height - insets.top - insets.bottom) / 2
        )
    }

    var canvasFrame: CGRect {
        let size = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
        return CGRect(
            x: restingCenter.x + pan.width - size.width / 2,
            y: restingCenter.y + pan.height - size.height / 2,
            width: size.width, height: size.height
        )
    }

    /// Canvas pixels to view points.
    var transform: CGAffineTransform {
        let frame = canvasFrame
        return CGAffineTransform(translationX: frame.minX, y: frame.minY).scaledBy(x: scale, y: scale)
    }

    func screenPoint(_ canvasPoint: CGPoint) -> CGPoint {
        canvasPoint.applying(transform)
    }

    func canvasPoint(_ screenPoint: CGPoint) -> CGPoint {
        screenPoint.applying(transform.inverted())
    }
}
