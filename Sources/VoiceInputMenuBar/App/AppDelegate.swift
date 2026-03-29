import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = AppMainMenu.make()
        coordinator = AppCoordinator()
        coordinator?.start()
    }
}
