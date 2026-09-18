import AppKit
import ApplicationServices
import os

private let log = Logger(subsystem: "com.plexy.fancyscroll", category: "edge")

enum ScrollEdge: Equatable {
    case top, bottom, left, right
}

/// Figures out whether the scroll view under the cursor has hit an edge, by reading the
/// scroll bar values of the accessibility element under the pointer.
///
/// All Accessibility calls happen on a private serial queue with a short messaging timeout so a
/// sluggish target app can never stall the event stream. Results come back on the main queue.
final class ScrollEdgeDetector {
    /// Called on the main queue when the user pushes into an edge they weren't already against.
    var onEdgeHit: ((ScrollEdge) -> Void)?

    private let queue = DispatchQueue(label: "fancyscroll.ax", qos: .userInteractive)
    private let systemWide = AXUIElementCreateSystemWide()

    // Queue-confined state
    private var scrollArea: AXUIElement?
    /// AppKit / WebKit expose scroll bars whose AXValue is 0…1.
    private var vBar: AXUIElement?
    private var hBar: AXUIElement?
    /// Chromium / Electron and scroller-less views don't; for those we compare the content
    /// element's frame with the viewport's frame instead.
    private var frameContent: AXUIElement?
    private var resolvedAt: TimeInterval = 0
    private var resolvedPoint = CGPoint.zero
    private var edgeHeld: ScrollEdge?
    private var pushIntoEdge: CGFloat = 0
    private var lastRead: TimeInterval = 0

    // Shared between caller thread and queue
    private let pendingLock = NSLock()
    private var pending = 0

    private let edgeEpsilon: CGFloat = 0.002
    /// Points of travel into an edge before we call it a hit (filters out finger jitter).
    private let pushThreshold: CGFloat = 6
    private let minReadInterval: TimeInterval = 0.025

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    init() {
        AXUIElementSetMessagingTimeout(systemWide, 0.05)
    }

    /// A new trackpad gesture began under the pointer at `point` (Cocoa screen coordinates).
    func beginGesture(at point: CGPoint) {
        queue.async {
            self.resolve(at: point)
            self.edgeHeld = nil
            self.pushIntoEdge = 0
        }
    }

    func endGesture() {
        queue.async {
            self.edgeHeld = nil
            self.pushIntoEdge = 0
        }
    }

    /// Feed a scroll delta. `isDiscrete` is true for phase-less events (classic mouse wheels),
    /// which don't have a gesture start we can hook, so we re-resolve lazily.
    func scrolled(dx: CGFloat, dy: CGFloat, at point: CGPoint, isDiscrete: Bool) {
        guard Self.isTrusted else { return }
        // Drop events rather than queue them up if the target app is answering slowly.
        pendingLock.lock()
        let backlog = pending
        if backlog < 2 { pending += 1 }
        pendingLock.unlock()
        guard backlog < 2 else { return }

        queue.async {
            defer {
                self.pendingLock.lock()
                self.pending -= 1
                self.pendingLock.unlock()
            }
            let now = CACurrentMediaTime()
            guard now - self.lastRead >= self.minReadInterval else { return }

            if isDiscrete {
                let stale = now - self.resolvedAt > 0.6
                let moved = hypot(point.x - self.resolvedPoint.x, point.y - self.resolvedPoint.y) > 12
                if self.scrollArea == nil || stale || moved {
                    self.resolve(at: point)
                }
            }
            guard self.scrollArea != nil else { return }
            self.lastRead = now

            let edge = self.edgeBeingPushed(dx: dx, dy: dy)
            if let edge {
                if self.edgeHeld == edge {
                    return // already reported this contact
                }
                self.pushIntoEdge += max(abs(dx), abs(dy))
                if self.pushIntoEdge >= self.pushThreshold {
                    self.edgeHeld = edge
                    self.pushIntoEdge = 0
                    DispatchQueue.main.async { self.onEdgeHit?(edge) }
                }
            } else {
                self.edgeHeld = nil
                self.pushIntoEdge = 0
            }
        }
    }

    // MARK: - Queue-confined helpers

    private func edgeBeingPushed(dx: CGFloat, dy: CGFloat) -> ScrollEdge? {
        let vertical = abs(dy) >= abs(dx)
        if vBar != nil || hBar != nil {
            return edgeFromScrollBars(dx: dx, dy: dy, vertical: vertical)
        }
        if let area = scrollArea, let content = frameContent {
            return edgeFromFrames(area: area, content: content, dx: dx, dy: dy, vertical: vertical)
        }
        return nil
    }

    private func edgeFromScrollBars(dx: CGFloat, dy: CGFloat, vertical: Bool) -> ScrollEdge? {
        // Positive scrollingDeltaY means "scroll up" (toward the top of the content) in AppKit.
        if vertical, dy != 0, let v = value(of: vBar) {
            if dy > 0 && v <= edgeEpsilon { return .top }
            if dy < 0 && v >= 1 - edgeEpsilon { return .bottom }
        } else if !vertical, dx != 0, let h = value(of: hBar) {
            if dx > 0 && h <= edgeEpsilon { return .left }
            if dx < 0 && h >= 1 - edgeEpsilon { return .right }
        }
        return nil
    }

    /// Geometry fallback: the content is at the top when its top edge isn't above the viewport,
    /// at the bottom when its bottom edge isn't below it. Only trusted when the content is
    /// actually larger than the viewport, so a sparse/placeholder tree can't cause false hits.
    private func edgeFromFrames(area: AXUIElement, content: AXUIElement, dx: CGFloat, dy: CGFloat, vertical: Bool) -> ScrollEdge? {
        guard let a = frame(of: area), let c = frame(of: content) else { return nil }
        let slack: CGFloat = 1.5
        if vertical, dy != 0 {
            guard c.height > a.height + slack else { return nil }
            if dy > 0 && c.minY >= a.minY - slack { return .top }
            if dy < 0 && c.maxY <= a.maxY + slack { return .bottom }
        } else if !vertical, dx != 0 {
            guard c.width > a.width + slack else { return nil }
            if dx > 0 && c.minX >= a.minX - slack { return .left }
            if dx < 0 && c.maxX <= a.maxX + slack { return .right }
        }
        return nil
    }

    private func resolve(at point: CGPoint) {
        scrollArea = nil
        vBar = nil
        hBar = nil
        frameContent = nil
        resolvedAt = CACurrentMediaTime()
        resolvedPoint = point

        // AX uses a top-left origin on the primary display.
        guard let primary = NSScreen.screens.first else { return }
        let axPoint = CGPoint(x: point.x, y: primary.frame.height - point.y)

        var raw: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(axPoint.x), Float(axPoint.y), &raw) == .success, let hit = raw else { return }

        // Walk up from the innermost element until we find something scrollable.
        var current: AXUIElement? = hit
        var depth = 0
        while let el = current, depth < 30 {
            AXUIElementSetMessagingTimeout(el, 0.05)

            // 1. Real scroll bars (AppKit, WebKit/Safari, Catalyst).
            let v = child(el, kAXVerticalScrollBarAttribute)
            let h = child(el, kAXHorizontalScrollBarAttribute)
            if v != nil || h != nil {
                scrollArea = el
                vBar = v
                hBar = h
                log.debug("resolved via scroll bars (depth \(depth))")
                return
            }

            // 2. Viewport-like containers without exposed scroll bars: compare frames.
            let role = string(el, kAXRoleAttribute)
            if role == kAXScrollAreaRole || role == "AXWebArea" {
                if let content = contentElement(of: el) {
                    scrollArea = el
                    frameContent = content
                    log.debug("resolved via frames of \(role ?? "?", privacy: .public) (depth \(depth))")
                    return
                }
            }

            current = child(el, kAXParentAttribute)
            depth += 1
        }
        log.debug("no scrollable container under pointer")
    }

    /// The element whose frame represents the full scrollable content of `viewport`:
    /// AXContents when available, otherwise the tallest child.
    private func contentElement(of viewport: AXUIElement) -> AXUIElement? {
        if let contents = elements(viewport, kAXContentsAttribute), let first = contents.first {
            return first
        }
        guard let children = elements(viewport, kAXChildrenAttribute), !children.isEmpty else { return nil }
        var best: (AXUIElement, CGFloat)?
        for c in children.prefix(8) {
            let h = frame(of: c)?.height ?? 0
            if best == nil || h > best!.1 { best = (c, h) }
        }
        return best?.0
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private func child(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func value(of bar: AXUIElement?) -> CGFloat? {
        guard let bar else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXValueAttribute as CFString, &value) == .success,
              let number = value as? NSNumber else { return nil }
        return CGFloat(number.doubleValue)
    }
}
