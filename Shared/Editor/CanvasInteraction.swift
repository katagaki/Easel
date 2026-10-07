import SwiftUI
import UIKit

/// Turns touches on the canvas into tool strokes and navigation.
///
/// One finger (or Apple Pencil) works the tool in hand; two fingers pinch
/// and pan the view. A second finger landing mid-stroke abandons the stroke,
/// since it was the start of a pinch. Tapping with two fingers undoes and
/// with three redoes, as in other drawing apps.
struct CanvasInteraction: UIViewRepresentable {
    var began: (StrokeGestureRecognizer.Sample) -> Void
    var moved: ([StrokeGestureRecognizer.Sample]) -> Void
    var ended: (Bool, CGPoint) -> Void
    var cancelled: () -> Void
    var zoomed: (Double, CGPoint) -> Void
    var panned: (CGSize) -> Void
    var undo: () -> Void
    var redo: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        let coordinator = context.coordinator

        let stroke = StrokeGestureRecognizer(target: coordinator, action: #selector(Coordinator.stroke(_:)))
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinch(_:)))
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.pan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.allowedScrollTypesMask = .continuous
        let undo = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.undo(_:)))
        undo.numberOfTouchesRequired = 2
        let redo = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.redo(_:)))
        redo.numberOfTouchesRequired = 3
        for recognizer in [stroke, pinch, pan, undo, redo] as [UIGestureRecognizer] {
            recognizer.delegate = coordinator
            view.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CanvasInteraction
        private var lastPinchScale: CGFloat = 1
        private var lastPanTranslation: CGPoint = .zero

        init(_ parent: CanvasInteraction) {
            self.parent = parent
        }

        @objc func stroke(_ recognizer: StrokeGestureRecognizer) {
            switch recognizer.state {
            case .began:
                if let first = recognizer.samples.first {
                    parent.began(first)
                    let rest = Array(recognizer.samples.dropFirst())
                    if !rest.isEmpty { parent.moved(rest) }
                }
                recognizer.samples.removeAll()
            case .changed:
                parent.moved(recognizer.samples)
                recognizer.samples.removeAll()
            case .ended:
                if !recognizer.samples.isEmpty {
                    parent.moved(recognizer.samples)
                    recognizer.samples.removeAll()
                }
                parent.ended(recognizer.isTap, recognizer.lastLocation)
            case .cancelled, .failed:
                recognizer.samples.removeAll()
                parent.cancelled()
            default:
                break
            }
        }

        @objc func pinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                lastPinchScale = 1
            case .changed:
                let factor = recognizer.scale / lastPinchScale
                lastPinchScale = recognizer.scale
                parent.zoomed(factor, recognizer.location(in: recognizer.view))
            default:
                break
            }
        }

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                lastPanTranslation = .zero
            case .changed:
                let translation = recognizer.translation(in: recognizer.view)
                parent.panned(CGSize(
                    width: translation.x - lastPanTranslation.x, height: translation.y - lastPanTranslation.y
                ))
                lastPanTranslation = translation
            default:
                break
            }
        }

        @objc func undo(_ recognizer: UITapGestureRecognizer) {
            parent.undo()
        }

        @objc func redo(_ recognizer: UITapGestureRecognizer) {
            parent.redo()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer
        ) -> Bool {
            // Two fingers tapping is an undo, not the start of a three
            // finger redo.
            gestureRecognizer.numberOfTouchesForTap == 2 && other.numberOfTouchesForTap == 3
        }
    }
}

private extension UIGestureRecognizer {
    var numberOfTouchesForTap: Int? {
        (self as? UITapGestureRecognizer)?.numberOfTouchesRequired
    }
}

/// Follows a single touch closely enough to draw with: every coalesced
/// sample, with Apple Pencil pressure and tilt. Begins at once so a stroke starts
/// where the finger landed, and cancels if a second finger arrives.
final class StrokeGestureRecognizer: UIGestureRecognizer {
    struct Sample {
        var location: CGPoint
        var pressure: Double
        /// Apple Pencil's lean and how upright it is; nil for a finger.
        var azimuth: Double?
        var altitude: Double?
    }

    /// Samples not yet handed on.
    var samples: [Sample] = []
    private(set) var lastLocation: CGPoint = .zero
    /// Whether the touch lifted close to where it landed, soon after.
    private(set) var isTap = false

    private var trackedTouch: UITouch?
    private var startLocation: CGPoint = .zero
    private var startTime: TimeInterval = 0
    private var travelled: CGFloat = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if trackedTouch != nil || touches.count > 1 || (event.allTouches?.count ?? 0) > 1 {
            state = state == .possible ? .failed : .cancelled
            return
        }
        guard let touch = touches.first else { return }
        trackedTouch = touch
        startLocation = touch.location(in: view)
        lastLocation = startLocation
        startTime = touch.timestamp
        travelled = 0
        isTap = false
        samples = [sample(touch)]
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        let coalesced = event.coalescedTouches(for: touch) ?? [touch]
        for item in coalesced {
            let location = item.location(in: view)
            travelled += hypot(location.x - lastLocation.x, location.y - lastLocation.y)
            lastLocation = location
            samples.append(sample(item))
        }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        lastLocation = touch.location(in: view)
        isTap = travelled < 10 && touch.timestamp - startTime < 0.35
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
        samples = []
        isTap = false
    }

    private func sample(_ touch: UITouch) -> Sample {
        let isPencil = touch.type == .pencil
        let pressure: Double = isPencil && touch.maximumPossibleForce > 0
            ? Double(touch.force / touch.maximumPossibleForce) : 1
        return Sample(
            location: touch.location(in: view), pressure: pressure,
            azimuth: isPencil ? Double(touch.azimuthAngle(in: view)) : nil,
            altitude: isPencil ? Double(touch.altitudeAngle) : nil
        )
    }
}
