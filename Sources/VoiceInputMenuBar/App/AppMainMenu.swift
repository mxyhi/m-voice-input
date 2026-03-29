import AppKit

@MainActor
enum AppMainMenu {
    static func make() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(editMenuItem())
        return mainMenu
    }

    private static func appMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: appName)

        submenu.addItem(
            NSMenuItem(
                title: "关于 \(appName)",
                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                keyEquivalent: ""
            )
        )
        submenu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: "隐藏 \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.target = NSApp
        submenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(
            title: "隐藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp
        submenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(
            title: "显示全部",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        showAllItem.target = NSApp
        submenu.addItem(showAllItem)

        submenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        submenu.addItem(quitItem)

        item.submenu = submenu
        return item
    }

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu(title: "编辑")

        submenu.addItem(makeItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))

        let redoItem = makeItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        submenu.addItem(redoItem)

        submenu.addItem(.separator())
        submenu.addItem(makeItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        submenu.addItem(makeItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        submenu.addItem(makeItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        submenu.addItem(makeItem(title: "删除", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        submenu.addItem(.separator())
        submenu.addItem(makeItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        item.submenu = submenu
        return item
    }

    private static func makeItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = nil
        return item
    }

    private static var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "MVoiceInput"
    }
}
