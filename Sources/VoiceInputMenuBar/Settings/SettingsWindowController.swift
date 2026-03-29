import AppKit
import SwiftUI
import VoiceInputCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private let viewModel: SettingsViewModel

    init(
        initialSettings: AppSettings,
        onSave: @escaping @MainActor (AppSettings) -> Void,
        onTest: @escaping @MainActor (AppSettings) async throws -> String
    ) {
        viewModel = SettingsViewModel(
            initialSettings: initialSettings,
            onSave: onSave,
            onTest: onTest
        )

        let view = SettingsView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 280))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(settings: AppSettings) {
        viewModel.reload(settings)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
