import CoreGraphics
import Foundation

/// One path in a vector layer.
struct VectorPathRef: Equatable, Sendable {
    var layerID: Layer.ID
    var path: Int
}

/// One point of a path in a vector layer.
struct VectorNodeRef: Equatable, Sendable {
    var layerID: Layer.ID
    var path: Int
    var node: Int

    var pathRef: VectorPathRef { VectorPathRef(layerID: layerID, path: path) }
}

/// What a drag on a path is moving. Starting points are in canvas pixels:
/// a layer's own coordinates move as its paths grow.
enum VectorDrag {
    /// A new point's handle being pulled out by the pen.
    case penHandle(VectorNodeRef, start: CGPoint)
    case anchor(VectorNodeRef, original: VectorNode, start: CGPoint)
    case handleIn(VectorNodeRef)
    case handleOut(VectorNodeRef)
}

extension EditorState {
    /// How close, in screen points, a touch has to be to grab a point.
    static let vectorReach = 22.0

    var vectorReachInCanvas: Double { Self.vectorReach / max(viewport.scale, 0.0001) }

    /// Changes one vector layer's paths, given in its own coordinates.
    func updateVector(_ layerID: Layer.ID, _ change: (inout VectorContent) -> Void) {
        update { composition in
            guard var layer = composition[layerID], var content = layer.vector else { return }
            change(&content)
            layer.setVector(content)
            composition[layerID] = layer
        }
    }

    // MARK: - Pen

    func penBegan(at point: CGPoint) {
        if let target = penPath, let layer = composition[target.layerID], let content = layer.vector,
           content.paths.indices.contains(target.path) {
            guard !layer.isLocked else { return }
            let local = layer.localPoint(point)
            let nodes = content.paths[target.path].nodes
            // Back on the first point: the shape is closed and finished.
            if nodes.count > 1, hypot(nodes[0].point.x - local.x, nodes[0].point.y - local.y)
                < vectorReachInCanvas / max(layer.transform.uniformScale, 0.0001) {
                updateVector(target.layerID) { $0.paths[target.path].isClosed = true }
                penPath = nil
                selectedNode = nil
                return
            }
            updateVector(target.layerID) { $0.paths[target.path].nodes.append(VectorNode(point: local)) }
            let node = VectorNodeRef(layerID: target.layerID, path: target.path, node: nodes.count)
            selectedNode = node
            vectorDrag = .penHandle(node, start: point)
            return
        }
        // A new path on a layer of its own.
        let path = VectorPath(
            nodes: [VectorNode(point: point)], isClosed: false,
            fill: shapeIsFilled ? color : nil, stroke: color, strokeWidth: shapeLineWidth
        )
        let layer = Layer.vector([path], name: String(localized: "Layer.DefaultName.Path"))
        update { $0.insert(layer, above: activeLayerID) }
        activeLayerID = layer.id
        penPath = VectorPathRef(layerID: layer.id, path: 0)
        let node = VectorNodeRef(layerID: layer.id, path: 0, node: 0)
        selectedNode = node
        vectorDrag = .penHandle(node, start: point)
    }

    /// Dragging after placing a point pulls out its handles, making a curve.
    func penMoved(to point: CGPoint) {
        guard case .penHandle(let node, let start) = vectorDrag, let layer = composition[node.layerID] else { return }
        let local = layer.localPoint(point)
        // A short wobble keeps a sharp corner.
        guard hypot(point.x - start.x, point.y - start.y) > vectorReachInCanvas / 4 else { return }
        updateVector(node.layerID) { content in
            guard content.paths.indices.contains(node.path),
                  content.paths[node.path].nodes.indices.contains(node.node) else { return }
            let anchor = content.paths[node.path].nodes[node.node].point
            content.paths[node.path].nodes[node.node] = .smooth(at: anchor, handle: local)
        }
    }

    /// Leaves the path open, as it is.
    func finishPath() {
        penPath = nil
    }
}
