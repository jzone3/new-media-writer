import AppKit

/// Wheel events that land on overlays (the view switcher, Copy / counter pills) would otherwise be
/// swallowed by the hosting view; forward them to the scroll view underneath so scrolling works anywhere.
enum ScrollPassthrough {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let content = event.window?.contentView else { return event }
            let point = content.convert(event.locationInWindow, from: nil)
            guard let hit = content.hitTest(point) else { return event }
            if hit is NSScrollView || hit.enclosingScrollView != nil { return event }
            guard let scroll = deepestScrollView(in: content, containing: point) else { return event }
            scroll.scrollWheel(with: event)
            return nil
        }
    }

    private static func deepestScrollView(in view: NSView, containing point: NSPoint) -> NSScrollView? {
        for sub in view.subviews.reversed() where !sub.isHidden {
            let local = sub.convert(point, from: view)
            guard sub.bounds.contains(local) else { continue }
            if let found = deepestScrollView(in: sub, containing: local) { return found }
            if let scroll = sub as? NSScrollView { return scroll }
        }
        return nil
    }
}
