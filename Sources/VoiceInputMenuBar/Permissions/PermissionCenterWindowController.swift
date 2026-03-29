import AppKit
import SwiftUI

@MainActor
final class PermissionCenterWindowController: NSWindowController {
    private let viewModel: PermissionCenterViewModel

    init(
        snapshotProvider: @escaping @MainActor () -> PermissionSnapshot,
        diagnosticsProvider: @escaping @MainActor () -> PermissionDiagnostics,
        requestPermission: @escaping @MainActor (PermissionKind) async -> PermissionSnapshot,
        requestAllMissing: @escaping @MainActor () async -> PermissionSnapshot,
        openSystemSettings: @escaping @MainActor () -> Void,
        onPermissionsChanged: @escaping @MainActor (PermissionSnapshot) -> Void
    ) {
        viewModel = PermissionCenterViewModel(
            snapshotProvider: snapshotProvider,
            diagnosticsProvider: diagnosticsProvider,
            requestPermission: requestPermission,
            requestAllMissing: requestAllMissing,
            openSystemSettings: openSystemSettings,
            onPermissionsChanged: onPermissionsChanged
        )

        let view = PermissionCenterView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "权限中心"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 620, height: 420))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        viewModel.reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
