import Carbon.HIToolbox
import CoreGraphics
import Foundation

final class FnKeyMonitor {
    private let onPress: @Sendable () -> Void
    private let onRelease: @Sendable () -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnIsPressed = false

    var isActive: Bool {
        eventTap != nil
    }

    init(onPress: @escaping @Sendable () -> Void, onRelease: @escaping @Sendable () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
    }

    @discardableResult
    func start(promptIfNeeded: Bool = true) -> Bool {
        guard eventTap == nil else {
            return true
        }

        if !CGPreflightListenEventAccess() {
            if promptIfNeeded {
                _ = CGRequestListenEventAccess()
            }
            return false
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passRetained(event)
            }

            let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        fnIsPressed = false
    }

    @discardableResult
    func restart() -> Bool {
        stop()
        return start(promptIfNeeded: false)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

            return Unmanaged.passRetained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Int64(kVK_Function) else {
            return Unmanaged.passRetained(event)
        }

        let isPressed = event.flags.contains(.maskSecondaryFn)
        let hasOtherModifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty == false
        if hasOtherModifiers {
            return Unmanaged.passRetained(event)
        }

        guard isPressed != fnIsPressed else {
            return nil
        }

        fnIsPressed = isPressed
        DispatchQueue.main.async { [onPress, onRelease] in
            if isPressed {
                onPress()
            } else {
                onRelease()
            }
        }

        // 抑制 Fn 事件，避免系统继续处理并弹出 emoji 面板。
        return nil
    }
}
