import AppKit

/// ホバー時にポインターカーソル＆スケールアニメーションするボタン
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
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 0.7
        }
        // 少し拡大
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            let scale = CATransform3DMakeScale(1.1, 1.1, 1.0)
            self.layer?.transform = scale
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.layer?.transform = CATransform3DIdentity
        }
    }

    override func mouseDown(with event: NSEvent) {
        // 押下時に縮小
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.05
            let scale = CATransform3DMakeScale(0.9, 0.9, 1.0)
            self.layer?.transform = scale
        }
        super.mouseDown(with: event)
        // マウスアップ後に戻す
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.layer?.transform = CATransform3DIdentity
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
}
