import AppKit

final class OverlayContentView: NSVisualEffectView {
    private let waveformView = WaveformBarsView(frame: NSRect(x: 0, y: 0, width: 44, height: 32))
    private let label = NSTextField(labelWithString: "开始说话…")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 28
        layer?.cornerCurve = .continuous

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.94)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1

        addSubview(waveformView)
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),
            waveformView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            waveformView.centerYAnchor.constraint(equalTo: centerYAnchor),
            waveformView.widthAnchor.constraint(equalToConstant: 44),
            waveformView.heightAnchor.constraint(equalToConstant: 32),
            label.leadingAnchor.constraint(equalTo: waveformView.trailingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        update(message: "开始说话…", levels: .idle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(message: String?, levels: [Double]?) {
        if let message {
            label.stringValue = message
        }

        if let levels {
            waveformView.update(levels: levels)
        }
    }

    func fittingSize(forHeight height: CGFloat) -> NSSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: label.font ?? NSFont.systemFont(ofSize: 16)]
        let rawWidth = label.stringValue.size(withAttributes: attributes).width
        let clampedTextWidth = min(max(rawWidth.rounded(.up), 160), 560)
        let width = 18 + 44 + 14 + clampedTextWidth + 20
        return NSSize(width: width, height: height)
    }
}

private extension Optional where Wrapped == [Double] {
    static var idle: Self {
        [0.18, 0.18, 0.18, 0.18, 0.18]
    }
}
