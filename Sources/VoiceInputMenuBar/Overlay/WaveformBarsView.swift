import AppKit

final class WaveformBarsView: NSView {
    private let barLayers = (0..<5).map { _ in CALayer() }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        for barLayer in barLayers {
            barLayer.backgroundColor = NSColor.white.withAlphaComponent(0.96).cgColor
            barLayer.cornerRadius = 2.8
            layer?.addSublayer(barLayer)
        }

        update(levels: [0.18, 0.18, 0.18, 0.18, 0.18])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(levels: [Double]) {
        let safeLevels = levels.count == 5 ? levels : [0.18, 0.18, 0.18, 0.18, 0.18]
        let width: CGFloat = 6
        let gap: CGFloat = 3.5
        let startX = (bounds.width - ((width * 5) + (gap * 4))) / 2

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))

        for (index, barLayer) in barLayers.enumerated() {
            let height = max(7, CGFloat(safeLevels[index]) * 32)
            let x = startX + CGFloat(index) * (width + gap)
            let y = (bounds.height - height) / 2
            barLayer.frame = NSRect(x: x, y: y, width: width, height: height)
        }

        CATransaction.commit()
    }
}
