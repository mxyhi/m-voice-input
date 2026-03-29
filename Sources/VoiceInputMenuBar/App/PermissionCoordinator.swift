import AVFoundation
import ApplicationServices
import Foundation
import Speech

enum PermissionSummary: String {
    case ready = "权限状态：就绪"
    case needsAccessibility = "权限状态：需开启辅助功能"
    case needsInputMonitoring = "权限状态：需开启输入监控"
    case needsEventInjection = "权限状态：需允许事件注入"
    case needsSpeech = "权限状态：需开启语音识别"
    case needsMicrophone = "权限状态：需开启麦克风"
    case unknown = "权限状态：待检查"
}

@MainActor
final class PermissionCoordinator {
    private(set) var permissionSummary: PermissionSummary = .unknown

    func refreshAccessibility(prompt: Bool) {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func makeSummary(inputMonitoringGranted: Bool) -> PermissionSummary {
        let accessibilityGranted = AXIsProcessTrusted()
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let canPostEvents = CGPreflightPostEventAccess()

        let summary: PermissionSummary
        if !accessibilityGranted {
            summary = .needsAccessibility
        } else if !inputMonitoringGranted {
            summary = .needsInputMonitoring
        } else if !canPostEvents {
            summary = .needsEventInjection
        } else if speechStatus != .authorized {
            summary = .needsSpeech
        } else if microphoneStatus != .authorized {
            summary = .needsMicrophone
        } else {
            summary = .ready
        }

        permissionSummary = summary
        return summary
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
