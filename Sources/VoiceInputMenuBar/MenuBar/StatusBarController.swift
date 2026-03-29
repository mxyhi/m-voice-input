import AppKit
import VoiceInputCore

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let languageProvider: () -> SupportedLanguage
    private let llmEnabledProvider: () -> Bool
    private let permissionsProvider: () -> PermissionSummary
    private let diagnosticsProvider: () -> [String]
    private let onLanguageSelected: (SupportedLanguage) -> Void
    private let onToggleLLM: (Bool) -> Void
    private let onOpenPermissions: () -> Void
    private let onOpenSettings: () -> Void
    private let onCopyDiagnostics: () -> Void
    private let onQuit: () -> Void

    private var permissionSummary: PermissionSummary = .unknown

    init(
        languageProvider: @escaping () -> SupportedLanguage,
        llmEnabledProvider: @escaping () -> Bool,
        permissionsProvider: @escaping () -> PermissionSummary,
        diagnosticsProvider: @escaping () -> [String],
        onLanguageSelected: @escaping (SupportedLanguage) -> Void,
        onToggleLLM: @escaping (Bool) -> Void,
        onOpenPermissions: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onCopyDiagnostics: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.languageProvider = languageProvider
        self.llmEnabledProvider = llmEnabledProvider
        self.permissionsProvider = permissionsProvider
        self.diagnosticsProvider = diagnosticsProvider
        self.onLanguageSelected = onLanguageSelected
        self.onToggleLLM = onToggleLLM
        self.onOpenPermissions = onOpenPermissions
        self.onOpenSettings = onOpenSettings
        self.onCopyDiagnostics = onCopyDiagnostics
        self.onQuit = onQuit
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "waveform.badge.mic",
                accessibilityDescription: "m-voice-input"
            )
            button.imagePosition = .imageOnly
        }
    }

    func refresh() {
        permissionSummary = permissionsProvider()
        statusItem.menu = buildMenu()
    }

    func updatePermissionSummary(_ summary: PermissionSummary) {
        permissionSummary = summary
        refresh()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let hintItem = NSMenuItem(title: "按住 Fn 开始录音，松开后注入文本", action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        menu.addItem(hintItem)

        let permissionItem = NSMenuItem(title: permissionSummary.rawValue, action: #selector(handleOpenPermissions), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        menu.addItem(.separator())
        menu.addItem(diagnosticsMenuItem())
        menu.addItem(languageMenuItem())
        menu.addItem(llmMenuItem())
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    private func diagnosticsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "运行诊断", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        for line in diagnosticsProvider() {
            let diagnosticLine = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            diagnosticLine.isEnabled = false
            submenu.addItem(diagnosticLine)
        }

        submenu.addItem(.separator())
        let copyItem = NSMenuItem(title: "复制运行诊断", action: #selector(handleCopyDiagnostics), keyEquivalent: "")
        copyItem.target = self
        submenu.addItem(copyItem)

        item.submenu = submenu
        return item
    }

    private func languageMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "语言", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let currentLanguage = languageProvider()

        for language in SupportedLanguage.menuOrderedCases {
            let option = NSMenuItem(
                title: language.displayName,
                action: #selector(handleLanguageSelection(_:)),
                keyEquivalent: ""
            )
            option.target = self
            option.representedObject = language
            option.state = currentLanguage == language ? .on : .off
            submenu.addItem(option)
        }

        item.submenu = submenu
        return item
    }

    private func llmMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let toggle = NSMenuItem(
            title: "启用",
            action: #selector(handleLLMToggle(_:)),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.state = llmEnabledProvider() ? .on : .off
        submenu.addItem(toggle)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(handleOpenSettings),
            keyEquivalent: ","
        )
        settings.target = self
        submenu.addItem(settings)

        item.submenu = submenu
        return item
    }

    @objc
    private func handleLanguageSelection(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? SupportedLanguage else {
            return
        }

        onLanguageSelected(language)
    }

    @objc
    private func handleLLMToggle(_ sender: NSMenuItem) {
        onToggleLLM(sender.state != .on)
    }

    @objc
    private func handleOpenPermissions() {
        onOpenPermissions()
    }

    @objc
    private func handleOpenSettings() {
        onOpenSettings()
    }

    @objc
    private func handleCopyDiagnostics() {
        onCopyDiagnostics()
    }

    @objc
    private func handleQuit() {
        onQuit()
    }
}
