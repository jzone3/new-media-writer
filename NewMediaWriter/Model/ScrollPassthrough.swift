import AppKit

/// Wheel events that land on overlays (the view switcher, Copy / counter pills) would otherwise be
/// swallowed by the hosting view; forward them to the scroll view underneath so scrolling works anywhere.
enum ScrollPassthrough {
    /// Posted for every wheel event this monitor consumes, since later local monitors never see it.
    static let didForwardWheel = Notification.Name("ScrollPassthrough.didForwardWheel")
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let content = event.window?.contentView else { return event }
            let point = content.convert(event.locationInWindow, from: nil)
            let hit = content.hitTest(point)
            if let hit, let scroll = hit as? NSScrollView ?? hit.enclosingScrollView {
                // A plain NSScrollView is our AppKit editor: it handles the wheel itself. SwiftUI's hosting
                // scroll view spans the whole window and swallows wheel events that hit-test to its clip view
                // or to overlay chrome (Copy pill, header), so drive it directly instead.
                if type(of: scroll) == NSScrollView.self { return event }
                scroll.scrollWheel(with: event)
                NotificationCenter.default.post(name: didForwardWheel, object: event.window)
                return nil
            }
            guard let scroll = deepestScrollView(in: content, containing: point) ?? anyScrollView(in: content) else { return event }
            scroll.scrollWheel(with: event)
            NotificationCenter.default.post(name: didForwardWheel, object: event.window)
            return nil
        }
    }

    private static func anyScrollView(in view: NSView) -> NSScrollView? {
        for sub in view.subviews where !sub.isHidden {
            if let scroll = sub as? NSScrollView { return scroll }
            if let found = anyScrollView(in: sub) { return found }
        }
        return nil
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
