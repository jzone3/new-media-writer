import AppKit

/// The Copy / counter pills and the view switcher float over the editor, inside its I-beam cursor rect,
/// so the text view has to notice when the pointer is over that chrome and show the arrow instead.
extension EditorTextView {
    func installOverlayCursorTracking() {
        if let overlayTracking { removeTrackingArea(overlayTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        overlayTracking = area
    }

    func updateCursorForOverlays(_ event: NSEvent) -> Bool {
        guard let content = window?.contentView else { return false }
        let point = content.convert(event.locationInWindow, from: nil)
        guard let hit = content.hitTest(point) else { return false }
        let editorRoot: NSView = enclosingScrollView ?? self
        let overOverlay = !(hit === editorRoot || hit.isDescendant(of: editorRoot))
        if overOverlay {
            NSCursor.arrow.set()
        } else if NSCursor.current == NSCursor.arrow {
            NSCursor.iBeam.set()
        }
        return overOverlay
    }
}
