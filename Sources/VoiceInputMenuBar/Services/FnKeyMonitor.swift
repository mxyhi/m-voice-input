import AppKit
import Carbon
import CoreGraphics
import Foundation

final class FnKeyMonitor: @unchecked Sendable {
    enum TriggerSource: String {
        case eventTap = "CGEventTap"
        case globalMonitor = "NSEvent Global"
        case localMonitor = "NSEvent Local"
        case releaseProbe = "Release Probe"
    }

    private enum Constants {
        static let functionKeyCode = UInt16(kVK_Function)
        static let releaseProbeInterval: TimeInterval = 0.05
        static let releaseProbeGracePeriod: TimeInterval = 0.20
        static let releaseProbeThreshold = 4
    }

    private let onPress: @Sendable (TriggerSource) -> Void
    private let onRelease: @Sendable (TriggerSource) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var releaseProbeTimer: Timer?
    private var fnIsPressed = false
    private var lastPressAt: Date?
    private var consecutiveReleaseProbeMisses = 0

    var isActive: Bool {
        eventTap != nil
    }

    init(
        onPress: @escaping @Sendable (TriggerSource) -> Void,
        onRelease: @escaping @Sendable (TriggerSource) -> Void
    ) {
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
        installFallbackMonitors()
        return true
    }

    func stop() {
        stopReleaseProbe()
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
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

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == Constants.functionKeyCode else {
            return Unmanaged.passRetained(event)
        }

        let isPressed = event.flags.contains(.maskSecondaryFn)
        let hasOtherModifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty == false
        if isPressed && hasOtherModifiers {
            return Unmanaged.passRetained(event)
        }

        DispatchQueue.main.async { [weak self] in
            self?.applyFnStateChange(isPressed: isPressed, source: .eventTap)
        }

        // 抑制 Fn 事件，避免系统继续处理并弹出 emoji 面板。
        return nil
    }

    private func installFallbackMonitors() {
        guard globalFlagsMonitor == nil, localFlagsMonitor == nil else {
            return
        }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFallback(event, source: .globalMonitor)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFallback(event, source: .localMonitor)
            return event
        }
    }

    private func handleFallback(_ event: NSEvent, source: TriggerSource) {
        guard event.keyCode == Constants.functionKeyCode else {
            return
        }

        let isPressed = event.modifierFlags.contains(.function)
        let hasOtherModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty == false

        if isPressed && hasOtherModifiers {
            return
        }

        applyFnStateChange(isPressed: isPressed, source: source)
    }

    private func applyFnStateChange(isPressed: Bool, source: TriggerSource) {
        guard isPressed != fnIsPressed else {
            return
        }

        fnIsPressed = isPressed
        consecutiveReleaseProbeMisses = 0

        if isPressed {
            lastPressAt = Date()
            startReleaseProbeIfNeeded()
            onPress(source)
        } else {
            stopReleaseProbe()
            onRelease(source)
        }
    }

    private func startReleaseProbeIfNeeded() {
        guard releaseProbeTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: Constants.releaseProbeInterval, repeats: true) { [weak self] _ in
            self?.probeForImplicitRelease()
        }
        releaseProbeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopReleaseProbe() {
        releaseProbeTimer?.invalidate()
        releaseProbeTimer = nil
        lastPressAt = nil
        consecutiveReleaseProbeMisses = 0
    }

    private func probeForImplicitRelease() {
        guard fnIsPressed else {
            stopReleaseProbe()
            return
        }

        guard let lastPressAt else {
            lastPressAt = Date()
            return
        }

        guard Date().timeIntervalSince(lastPressAt) >= Constants.releaseProbeGracePeriod else {
            return
        }

        let hidSystemContainsFn = CGEventSource.flagsState(.hidSystemState).contains(.maskSecondaryFn)
        let hidSystemKeyDown = CGEventSource.keyState(.hidSystemState, key: CGKeyCode(Constants.functionKeyCode))

        // 这里必须只看 HID 硬件层状态。
        // 我们在 session tap 中吞掉了 Fn 的 flagsChanged 事件，AppKit / combined session
        // 看到的 modifier 状态可能会滞留在“按下”，导致轮询永远误判未松手。
        let stillPressed = hidSystemContainsFn || hidSystemKeyDown
        if stillPressed {
            consecutiveReleaseProbeMisses = 0
            return
        }

        consecutiveReleaseProbeMisses += 1
        if consecutiveReleaseProbeMisses >= Constants.releaseProbeThreshold {
            applyFnStateChange(isPressed: false, source: .releaseProbe)
        }
    }
}
