import AppKit
import Carbon
import CoreGraphics

@MainActor
final class TextInjectionService {
    private let pasteboard = NSPasteboard.general
    private let inputSourceController = InputSourceController()

    func inject(text: String) async throws {
        guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
            throw TextInjectionError.eventInjectionPermissionDenied
        }

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let switchContext = inputSourceController.switchToASCIIIfNeeded()

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ownedChangeCount = pasteboard.changeCount

        try? await Task.sleep(for: .milliseconds(120))
        postCommandV()
        try? await Task.sleep(for: .milliseconds(120))

        inputSourceController.restoreIfOwned(switchContext)

        try? await Task.sleep(for: .milliseconds(80))
        snapshot.restoreIfOwned(to: pasteboard, ownedChangeCount: ownedChangeCount)
    }

    private func postCommandV() {
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

enum TextInjectionError: LocalizedError {
    case eventInjectionPermissionDenied

    var errorDescription: String? {
        switch self {
        case .eventInjectionPermissionDenied:
            return "未获得事件注入权限"
        }
    }
}

private struct PasteboardSnapshot {
    struct Item {
        let entries: [(NSPasteboard.PasteboardType, Data)]
    }

    let items: [Item]
    let originalChangeCount: Int

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { pasteboardItem in
            let entries = pasteboardItem.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let data = pasteboardItem.data(forType: type) else {
                    return nil
                }

                return (type, data)
            }

            return Item(entries: entries)
        }

        return PasteboardSnapshot(items: items, originalChangeCount: pasteboard.changeCount)
    }

    func restoreIfOwned(to pasteboard: NSPasteboard, ownedChangeCount: Int) {
        guard pasteboard.changeCount == ownedChangeCount else {
            return
        }

        pasteboard.clearContents()

        for item in items {
            let restored = NSPasteboardItem()
            for (type, data) in item.entries {
                restored.setData(data, forType: type)
            }

            pasteboard.writeObjects([restored])
        }
    }
}

private final class InputSourceController {
    struct SwitchContext {
        let originalSourceID: String
        let temporarySourceID: String
        let originalSource: TISInputSource
    }

    func switchToASCIIIfNeeded() -> SwitchContext? {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }

        guard isCJKInputSource(currentSource) else {
            return nil
        }

        guard let asciiSource = findPreferredASCIISource() else {
            return nil
        }

        let originalSourceID = sourceID(for: currentSource)
        let temporarySourceID = sourceID(for: asciiSource)
        TISSelectInputSource(asciiSource)
        return SwitchContext(
            originalSourceID: originalSourceID,
            temporarySourceID: temporarySourceID,
            originalSource: currentSource
        )
    }

    func restoreIfOwned(_ context: SwitchContext?) {
        guard
            let context,
            let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            sourceID(for: currentSource) == context.temporarySourceID
        else {
            return
        }

        TISSelectInputSource(context.originalSource)
    }

    private func findPreferredASCIISource() -> TISInputSource? {
        if let recentASCII = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() {
            let recentASCIIID = sourceID(for: recentASCII)
            if recentASCIIID == "com.apple.keylayout.ABC" || recentASCIIID == "com.apple.keylayout.US" {
                return recentASCII
            }
        }

        let filter = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary
        guard let inputSources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }

        let preferredIDs = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]
        for preferredID in preferredIDs {
            if let match = inputSources.first(where: { sourceID(for: $0) == preferredID }) {
                return match
            }
        }

        return TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue()
            ?? inputSources.first(where: { inputSourceType(for: $0) == kTISTypeKeyboardLayout as String })
    }

    private func isCJKInputSource(_ source: TISInputSource) -> Bool {
        let sourceID = sourceID(for: source)
        let languages = inputLanguages(for: source)
        let inputType = inputSourceType(for: source)
        let hasCJKLanguage = languages.contains { language in
            language.hasPrefix("zh") || language.hasPrefix("ja") || language.hasPrefix("ko")
        }
        let isKeyboardLayout = inputType == kTISTypeKeyboardLayout as String
        return sourceID.contains("inputmethod") && hasCJKLanguage && !isKeyboardLayout
    }

    private func sourceID(for source: TISInputSource) -> String {
        propertyValue(for: source, key: kTISPropertyInputSourceID) ?? ""
    }

    private func inputSourceType(for source: TISInputSource) -> String {
        propertyValue(for: source, key: kTISPropertyInputSourceType) ?? ""
    }

    private func inputLanguages(for source: TISInputSource) -> [String] {
        propertyValue(for: source, key: kTISPropertyInputSourceLanguages) ?? []
    }

    private func propertyValue<T>(for source: TISInputSource, key: CFString) -> T? {
        guard let raw = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        let object = Unmanaged<CFTypeRef>.fromOpaque(raw).takeUnretainedValue()
        return object as? T
    }
}
