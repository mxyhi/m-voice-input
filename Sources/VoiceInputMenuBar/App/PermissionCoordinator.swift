import AVFoundation
import ApplicationServices
import AppKit
import Foundation
import Speech

enum PermissionSummary: String {
    case ready = "权限状态：就绪"
    case needsInputMonitoring = "权限状态：需开启输入监控"
    case needsEventInjection = "权限状态：需允许事件注入"
    case needsSpeech = "权限状态：需开启语音识别"
    case needsMicrophone = "权限状态：需开启麦克风"
    case unknown = "权限状态：待检查"
}

enum PermissionKind: String, CaseIterable, Identifiable {
    case inputMonitoring
    case eventInjection
    case speechRecognition
    case microphone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inputMonitoring:
            "输入监控"
        case .eventInjection:
            "事件注入"
        case .speechRecognition:
            "语音识别"
        case .microphone:
            "麦克风"
        }
    }

    var detail: String {
        switch self {
        case .inputMonitoring:
            "用于全局监听 Fn 键按下和松开。"
        case .eventInjection:
            "用于模拟发送 Cmd+V，把转录结果注入当前输入框。"
        case .speechRecognition:
            "用于把录制的语音实时转写为文本。"
        case .microphone:
            "用于采集按住 Fn 时的麦克风音频。"
        }
    }
}

struct PermissionSnapshot {
    struct Item: Identifiable {
        let kind: PermissionKind
        let isGranted: Bool

        var id: String { kind.id }
    }

    let inputMonitoringGranted: Bool
    let eventInjectionGranted: Bool
    let speechRecognitionGranted: Bool
    let microphoneGranted: Bool

    var summary: PermissionSummary {
        if !inputMonitoringGranted {
            .needsInputMonitoring
        } else if !eventInjectionGranted {
            .needsEventInjection
        } else if !speechRecognitionGranted {
            .needsSpeech
        } else if !microphoneGranted {
            .needsMicrophone
        } else {
            .ready
        }
    }

    var isReady: Bool {
        summary == .ready
    }

    var items: [Item] {
        [
            .init(kind: .inputMonitoring, isGranted: inputMonitoringGranted),
            .init(kind: .eventInjection, isGranted: eventInjectionGranted),
            .init(kind: .speechRecognition, isGranted: speechRecognitionGranted),
            .init(kind: .microphone, isGranted: microphoneGranted),
        ]
    }
}

struct PermissionDiagnostics {
    let bundleIdentifier: String
    let bundlePath: String
    let executablePath: String
    let isInstalledInApplications: Bool

    var summaryText: String {
        """
        Bundle ID: \(bundleIdentifier)
        Bundle Path: \(bundlePath)
        Executable: \(executablePath)
        安装位置有效: \(isInstalledInApplications ? "是" : "否")
        """
    }
}

@MainActor
final class PermissionCoordinator {
    private(set) var permissionSummary: PermissionSummary = .unknown

    func snapshot() -> PermissionSnapshot {
        let snapshot = PermissionSnapshot(
            inputMonitoringGranted: CGPreflightListenEventAccess(),
            eventInjectionGranted: CGPreflightPostEventAccess(),
            speechRecognitionGranted: SFSpeechRecognizer.authorizationStatus() == .authorized,
            microphoneGranted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        )
        permissionSummary = snapshot.summary
        return snapshot
    }

    func diagnostics() -> PermissionDiagnostics {
        let bundle = Bundle.main
        let bundleIdentifier = bundle.bundleIdentifier ?? "unknown"
        let bundlePath = bundle.bundleURL.path
        let executablePath = bundle.executableURL?.path ?? ProcessInfo.processInfo.arguments.first ?? "unknown"
        let applicationsDirectories = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)
            + FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask)
        let isInstalledInApplications = applicationsDirectories.contains { applicationsURL in
            bundlePath.hasPrefix(applicationsURL.path)
        }

        return PermissionDiagnostics(
            bundleIdentifier: bundleIdentifier,
            bundlePath: bundlePath,
            executablePath: executablePath,
            isInstalledInApplications: isInstalledInApplications
        )
    }

    func request(_ permission: PermissionKind) async -> PermissionSnapshot {
        switch permission {
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        case .eventInjection:
            _ = CGRequestPostEventAccess()
        case .speechRecognition:
            _ = await requestSpeechRecognitionIfNeeded()
        case .microphone:
            _ = await requestMicrophoneIfNeeded()
        }

        try? await Task.sleep(for: .milliseconds(250))
        let latest = snapshot()
        if item(for: permission, in: latest).isGranted == false {
            openSystemSettings(for: permission)
        }
        return latest
    }

    func requestMissingPermissions() async -> PermissionSnapshot {
        let permissionsInOrder: [PermissionKind] = [
            .microphone,
            .speechRecognition,
            .inputMonitoring,
            .eventInjection,
        ]

        var latest = snapshot()
        for permission in permissionsInOrder {
            if item(for: permission, in: latest).isGranted {
                continue
            }
            latest = await request(permission)
        }

        return latest
    }

    func openSystemSettings(for permission: PermissionKind? = nil) {
        let privacyURL: URL?
        switch permission {
        case .inputMonitoring:
            privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        case .eventInjection:
            privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .speechRecognition:
            privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .microphone:
            privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case nil:
            privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
        }

        if let privacyURL {
            NSWorkspace.shared.open(privacyURL)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
            configuration: configuration
        )
    }

    func item(for permission: PermissionKind, in snapshot: PermissionSnapshot) -> PermissionSnapshot.Item {
        snapshot.items.first(where: { $0.kind == permission }) ?? .init(kind: permission, isGranted: false)
    }

    func requestSpeechRecognitionIfNeeded() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        guard status == .notDetermined else {
            return status == .authorized
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { authorization in
                continuation.resume(returning: authorization == .authorized)
            }
        }
    }

    func requestMicrophoneIfNeeded() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .notDetermined else {
            return status == .authorized
        }

        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
