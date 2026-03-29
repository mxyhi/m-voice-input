import AppKit

@MainActor
final class OverlayPanelController {
    private let contentView = OverlayContentView()
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = contentView
        panel.orderOut(nil)
        return panel
    }()

    private var dismissTask: Task<Void, Never>?

    func show(message: String, levels: [Double]) {
        dismissTask?.cancel()
        contentView.update(message: message, levels: levels)
        resizePanel(animated: panel.isVisible)
        positionPanel()

        guard !panel.isVisible else {
            return
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        animateEntrance()
    }

    func updateTranscript(_ transcript: String) {
        let message = transcript.isEmpty ? "开始说话…" : transcript
        contentView.update(message: message, levels: nil)
        resizePanel(animated: true)
        positionPanel()
    }

    func updateWaveform(_ levels: [Double]) {
        contentView.update(message: nil, levels: levels)
    }

    func dismiss(after delay: TimeInterval = 0) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }

            animateExit()
        }
    }

    private func resizePanel(animated: Bool) {
        let size = contentView.fittingSize(forHeight: 56)
        var frame = panel.frame
        frame.size = size
        frame.origin.x = frame.midX - (size.width / 2)

        if animated, panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.minY + 48
        )
        panel.setFrameOrigin(origin)
    }

    private func animateEntrance() {
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.transform = CATransform3DMakeScale(0.92, 0.92, 1)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
        }

        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = CATransform3DMakeScale(0.92, 0.92, 1)
        spring.toValue = CATransform3DIdentity
        spring.mass = 0.9
        spring.damping = 18
        spring.stiffness = 160
        spring.initialVelocity = 6
        spring.duration = spring.settlingDuration
        panel.contentView?.layer?.add(spring, forKey: "entranceTransform")
        panel.contentView?.layer?.transform = CATransform3DIdentity
    }

    private func animateExit() {
        guard panel.isVisible else {
            return
        }

        panel.contentView?.wantsLayer = true
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = CATransform3DIdentity
        animation.toValue = CATransform3DMakeScale(0.94, 0.94, 1)
        animation.duration = 0.22
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        panel.contentView?.layer?.add(animation, forKey: "exitTransform")

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            self?.panel.orderOut(nil)
        }
    }
}
