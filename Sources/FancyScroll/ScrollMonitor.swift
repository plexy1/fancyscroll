import AppKit
import Combine
import os

private let log = Logger(subsystem: "com.plexy.fancyscroll", category: "scroll")

/// Watches every scroll-wheel event on the system and turns it into haptic ticks and
/// end-of-page bumps.
final class ScrollMonitor: ObservableObject {
    static let shared = ScrollMonitor()

    /// Stats for the UI.
    @Published private(set) var tickCount = 0
    @Published private(set) var edgeHitCount = 0
    @Published private(set) var lastEdge: ScrollEdge?

    private let settings = Settings.shared
    private let haptics = Haptics.shared
    private let edgeDetector = ScrollEdgeDetector()

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var accumX: CGFloat = 0
    private var accumY: CGFloat = 0
    private var inMomentum = false

    private init() {
        edgeDetector.onEdgeHit = { [weak self] edge in
            guard let self, self.settings.enabled, self.settings.endEnabled else { return }
            self.haptics.play(self.settings.endPattern, intensity: self.settings.endIntensity)
            self.edgeHitCount += 1
            self.lastEdge = edge
            log.info("edge hit: \(String(describing: edge), privacy: .public)")
        }
    }

    func start() {
        guard globalMonitor == nil else { return }
        log.info("monitor started; engine=\(self.haptics.activeEngineName, privacy: .public) ax=\(ScrollEdgeDetector.isTrusted)")
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    // MARK: - Event handling

    private func handle(_ event: NSEvent) {
        guard settings.enabled else { return }

        let phase = event.phase
        let momentum = event.momentumPhase
        let isDiscrete = phase.isEmpty && momentum.isEmpty // classic mouse wheel
        let point = NSEvent.mouseLocation

        // Gesture bookkeeping
        if phase.contains(.began) || phase.contains(.mayBegin) {
            accumX = 0
            accumY = 0
            inMomentum = false
            edgeDetector.beginGesture(at: point)
        }
        if momentum.contains(.began) {
            inMomentum = true
            // Momentum is a fresh run; don't carry over a partial step.
            accumX = 0
            accumY = 0
        }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            // Finger lifted. Momentum may follow and continues the same edge contact; the
            // detector is reset either when momentum ends or at the next .began.
            return
        }
        if momentum.contains(.ended) || momentum.contains(.cancelled) {
            inMomentum = false
            edgeDetector.endGesture()
            return
        }

        let momentumActive = !momentum.isEmpty
        if momentumActive && !settings.feedbackDuringMomentum {
            return // finger is lifted; nothing to feel
        }

        // Convert to points. Non-precise devices report lines; ~10 pt/line is a common mapping.
        var dx = event.scrollingDeltaX
        var dy = event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas {
            dx *= 10
            dy *= 10
        }
        guard dx != 0 || dy != 0 else { return }

        if settings.endEnabled {
            edgeDetector.scrolled(dx: dx, dy: dy, at: point, isDiscrete: isDiscrete)
        }

        if settings.stepsEnabled {
            tickIfNeeded(dy, accum: &accumY)
            if settings.horizontalSteps {
                tickIfNeeded(dx, accum: &accumX)
            }
        }
    }

    /// Accumulates travel along one axis and fires a tick every `stepSize` points.
    private func tickIfNeeded(_ delta: CGFloat, accum: inout CGFloat) {
        guard delta != 0 else { return }
        // Direction reversal: start counting again from zero.
        if (delta > 0 && accum < 0) || (delta < 0 && accum > 0) {
            accum = 0
        }
        accum += delta
        let step = CGFloat(max(settings.stepSize, 1))
        if abs(accum) >= step {
            // One tick per event even if the finger jumped several steps; keep the remainder
            // so slow scrolling stays evenly spaced.
            accum = accum.truncatingRemainder(dividingBy: step)
            haptics.tick(settings.stepIntensity)
            tickCount += 1
            log.debug("tick #\(self.tickCount)")
        }
    }
}
