import AppKit

/// ホバー時にポインターカーソル＆ハイライトするボタン
class HoverButton: NSButton {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        contentTintColor = .controlAccentColor
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        contentTintColor = .secondaryLabelColor
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentTintColor = .secondaryLabelColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        contentTintColor = .secondaryLabelColor
    }
}
