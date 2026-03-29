import AppKit
import Foundation
import OSLog
import Speech
import VoiceInputCore

@MainActor
final class AppCoordinator {
    private enum RecordingFinishReason {
        case fnRelease
        case silenceFallback
    }

    private enum RecordingFallback {
        static let silenceMonitorInterval: Duration = .milliseconds(150)
        static let minimumRecordingDuration: Duration = .milliseconds(900)
        static let silenceThreshold = 0.16
        static let transcriptIdleTimeout: Duration = .milliseconds(700)
        static let audioIdleTimeout: Duration = .milliseconds(900)
    }

    private let logger = Logger(subsystem: "com.langhuam.mvoiceinput", category: "AppCoordinator")
    private let diagnosticsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    private let settingsStore = AppSettingsStore()
    private let overlayController = OverlayPanelController()
    private let permissionCoordinator = PermissionCoordinator()
    private let textInjectionService = TextInjectionService()
    private let llmRefinementService = LLMRefinementService()

    private lazy var settingsWindowController = makeSettingsWindowController()
    private lazy var permissionCenterWindowController = makePermissionCenterWindowController()

    private lazy var speechController = SpeechRecognitionController(
        onTranscript: { [weak self] transcript in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                latestTranscript = transcript
                lastTranscriptUpdateAt = ContinuousClock.now

                guard isRecording, !isFinishingRecording else {
                    return
                }

                overlayController.updateTranscript(transcript)
            }
        },
        onWaveform: { [weak self] levels in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                if levels.contains(where: { $0 >= RecordingFallback.silenceThreshold }) {
                    lastAudioActivityAt = ContinuousClock.now
                }

                guard isRecording, !isFinishingRecording else {
                    return
                }

                overlayController.updateWaveform(levels)
            }
        }
    )

    private lazy var fnMonitor = FnKeyMonitor(
        onPress: { [weak self] source in
            Task { @MainActor [weak self] in
                self?.recordDiagnostic("收到 Fn 按下 [\(source.rawValue)]")
                await self?.beginRecording()
            }
        },
        onRelease: { [weak self] source in
            Task { @MainActor [weak self] in
                self?.recordDiagnostic("收到 Fn 松开 [\(source.rawValue)]")
                await self?.finishRecording()
            }
        }
    )

    private lazy var statusBarController = StatusBarController(
        languageProvider: { [weak self] in
            self?.settings.selectedLanguage ?? .defaultLanguage
        },
        llmEnabledProvider: { [weak self] in
            self?.settings.llm.isEnabled ?? false
        },
        permissionsProvider: { [weak self] in
            self?.permissionCoordinator.permissionSummary ?? .unknown
        },
        diagnosticsProvider: { [weak self] in
            self?.runtimeDiagnostics ?? ["暂无诊断信息"]
        },
        onLanguageSelected: { [weak self] language in
            self?.selectLanguage(language)
        },
        onToggleLLM: { [weak self] isEnabled in
            self?.toggleLLM(isEnabled)
        },
        onOpenPermissions: { [weak self] in
            self?.openPermissions()
        },
        onOpenSettings: { [weak self] in
            self?.openSettings()
        },
        onCopyDiagnostics: { [weak self] in
            self?.copyRuntimeDiagnostics()
        },
        onQuit: {
            NSApplication.shared.terminate(nil)
        }
    )

    private var settings: AppSettings
    private var latestTranscript = ""
    private var isRecording = false
    private var isFinishingRecording = false
    private var recordingStartedAt: ContinuousClock.Instant?
    private var lastAudioActivityAt: ContinuousClock.Instant?
    private var lastTranscriptUpdateAt: ContinuousClock.Instant?
    private var silenceMonitorTask: Task<Void, Never>?
    private var runtimeDiagnostics = ["等待 Fn"]

    init() {
        settings = settingsStore.load()
    }

    func start() {
        statusBarController.refresh()
        _ = fnMonitor.start()
        let snapshot = updatePermissionSummary()
        if !snapshot.isReady {
            permissionCenterWindowController.present()
        }
    }

    private func selectLanguage(_ language: SupportedLanguage) {
        settings.selectedLanguage = language
        settingsStore.save(settings)
        statusBarController.refresh()
    }

    private func toggleLLM(_ isEnabled: Bool) {
        settings.llm.isEnabled = isEnabled
        settingsStore.save(settings)
        statusBarController.refresh()
    }

    private func openSettings() {
        settingsWindowController.present(settings: settings)
    }

    private func openPermissions() {
        permissionCenterWindowController.present()
    }

    private func applySettings(_ updated: AppSettings) {
        settings = updated
        settingsStore.save(updated)
        statusBarController.refresh()
    }

    private func makeSettingsWindowController() -> SettingsWindowController {
        SettingsWindowController(
            initialSettings: settings,
            onSave: { [weak self] updated in
                self?.applySettings(updated)
            },
            onTest: { [weak self] candidate in
                guard let self else {
                    throw CancellationError()
                }

                return try await self.llmRefinementService.test(settings: candidate.llm)
            }
        )
    }

    private func makePermissionCenterWindowController() -> PermissionCenterWindowController {
        PermissionCenterWindowController(
            snapshotProvider: { [weak self] in
                self?.permissionCoordinator.snapshot() ?? PermissionSnapshot(
                    inputMonitoringGranted: false,
                    eventInjectionGranted: false,
                    speechRecognitionGranted: false,
                    microphoneGranted: false
                )
            },
            diagnosticsProvider: { [weak self] in
                self?.permissionCoordinator.diagnostics() ?? PermissionDiagnostics(
                    bundleIdentifier: "unknown",
                    bundlePath: "unknown",
                    executablePath: "unknown",
                    isInstalledInApplications: false
                )
            },
            requestPermission: { [weak self] permission in
                guard let self else {
                    return PermissionSnapshot(
                        inputMonitoringGranted: false,
                        eventInjectionGranted: false,
                        speechRecognitionGranted: false,
                        microphoneGranted: false
                    )
                }

                let snapshot = await self.permissionCoordinator.request(permission)
                if permission == .inputMonitoring {
                    _ = self.fnMonitor.restart()
                }
                return self.applyPermissionSnapshot(snapshot)
            },
            requestAllMissing: { [weak self] in
                guard let self else {
                    return PermissionSnapshot(
                        inputMonitoringGranted: false,
                        eventInjectionGranted: false,
                        speechRecognitionGranted: false,
                        microphoneGranted: false
                    )
                }

                let snapshot = await self.permissionCoordinator.requestMissingPermissions()
                _ = self.fnMonitor.restart()
                return self.applyPermissionSnapshot(snapshot)
            },
            openSystemSettings: { [weak self] in
                self?.permissionCoordinator.openSystemSettings()
            },
            onPermissionsChanged: { [weak self] snapshot in
                _ = self?.applyPermissionSnapshot(snapshot)
            }
        )
    }

    @discardableResult
    private func updatePermissionSummary() -> PermissionSnapshot {
        applyPermissionSnapshot(permissionCoordinator.snapshot())
    }

    @discardableResult
    private func applyPermissionSnapshot(_ snapshot: PermissionSnapshot) -> PermissionSnapshot {
        statusBarController.updatePermissionSummary(snapshot.summary)
        return snapshot
    }

    private func beginRecording() async {
        guard !isRecording else {
            return
        }

        logger.log("Begin recording requested")
        recordDiagnostic("开始校验权限")

        let snapshotBeforeRequest = permissionCoordinator.snapshot()
        let permissionSnapshot = await permissionCoordinator.requestMissingPermissions()
        let shouldRestartFnMonitor = !snapshotBeforeRequest.inputMonitoringGranted && permissionSnapshot.inputMonitoringGranted
        if shouldRestartFnMonitor {
            _ = fnMonitor.restart()
            recordDiagnostic("输入监控刚完成授权，重建 Fn 监听")
        }
        let refreshedSnapshot = updatePermissionSummary()

        guard permissionSnapshot.isReady && refreshedSnapshot.isReady else {
            recordDiagnostic("权限未完成，录音未启动")
            permissionCenterWindowController.present()
            overlayController.show(message: "请先完成权限授权", levels: .idle)
            overlayController.dismiss(after: 1.4)
            return
        }

        do {
            latestTranscript = ""
            recordingStartedAt = ContinuousClock.now
            lastAudioActivityAt = recordingStartedAt
            lastTranscriptUpdateAt = recordingStartedAt
            overlayController.show(message: "开始说话…", levels: .idle)
            try speechController.start(localeIdentifier: settings.selectedLanguage.localeIdentifier)
            isRecording = true
            startSilenceMonitor()
            logger.log("Recording started for locale \(self.settings.selectedLanguage.localeIdentifier, privacy: .public)")
            recordDiagnostic("录音已启动")
        } catch {
            logger.error("Recording failed to start: \(error.localizedDescription, privacy: .public)")
            recordDiagnostic("录音启动失败: \(error.localizedDescription)")
            overlayController.show(message: "录音启动失败", levels: .idle)
            overlayController.dismiss(after: 1.2)
        }
    }

    private func finishRecording() async {
        await finishRecording(reason: .fnRelease)
    }

    private func finishRecording(reason: RecordingFinishReason) async {
        guard !isFinishingRecording else {
            return
        }

        guard isRecording else {
            return
        }

        logger.log("Finish recording requested, reason: \(String(describing: reason), privacy: .public)")
        recordDiagnostic(reason == .fnRelease ? "开始收尾: Fn 松开" : "开始收尾: 静默兜底")
        isFinishingRecording = true
        isRecording = false
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        let stoppingMessage = reason == .fnRelease ? "停止中…" : "检测到停顿，收尾中…"
        overlayController.show(message: stoppingMessage, levels: .idle)
        let transcript = await speechController.stop()
        latestTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.log("Speech stop completed, transcript length: \(self.latestTranscript.count)")
        recordDiagnostic("停录完成，文本长度 \(latestTranscript.count)")

        guard !latestTranscript.isEmpty else {
            recordDiagnostic("未识别到语音")
            overlayController.show(message: "未识别到语音", levels: .idle)
            overlayController.dismiss(after: 0.9)
            isFinishingRecording = false
            return
        }

        let finalText: String
        if settings.llm.isEnabled && settings.llm.isConfigured {
            recordDiagnostic("开始 LLM refine")
            overlayController.show(message: "Refining...", levels: .idle)
            finalText = await refineTranscriptIfPossible(latestTranscript)
        } else {
            finalText = latestTranscript
        }

        overlayController.show(message: finalText, levels: .idle)

        do {
            recordDiagnostic("开始注入文本")
            overlayController.show(message: "正在注入…", levels: .idle)
            try await textInjectionService.inject(text: finalText)
            logger.log("Text injection succeeded")
            recordDiagnostic("注入成功")
        } catch {
            logger.error("Text injection failed: \(error.localizedDescription, privacy: .public)")
            recordDiagnostic("注入失败: \(error.localizedDescription)")
            overlayController.show(message: error.localizedDescription, levels: .idle)
            overlayController.dismiss(after: 1.2)
            isFinishingRecording = false
            return
        }

        overlayController.show(message: finalText, levels: .idle)
        overlayController.dismiss(after: 0.24)
        isFinishingRecording = false
        recordingStartedAt = nil
        lastAudioActivityAt = nil
        lastTranscriptUpdateAt = nil
    }

    private func refineTranscriptIfPossible(_ transcript: String) async -> String {
        do {
            return try await llmRefinementService.refine(transcript: transcript, settings: settings.llm)
        } catch {
            recordDiagnostic("LLM refine 失败，回退原文")
            return transcript
        }
    }

    private func startSilenceMonitor() {
        silenceMonitorTask?.cancel()
        silenceMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: RecordingFallback.silenceMonitorInterval)
                await self?.evaluateSilenceFallback()
            }
        }
    }

    private func evaluateSilenceFallback() async {
        guard isRecording, !isFinishingRecording else {
            return
        }

        guard
            let recordingStartedAt,
            let lastAudioActivityAt,
            let lastTranscriptUpdateAt
        else {
            return
        }

        let now = ContinuousClock.now
        guard now - recordingStartedAt >= RecordingFallback.minimumRecordingDuration else {
            return
        }

        guard !latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let audioIdle = now - lastAudioActivityAt
        let transcriptIdle = now - lastTranscriptUpdateAt
        guard audioIdle >= RecordingFallback.audioIdleTimeout else {
            return
        }
        guard transcriptIdle >= RecordingFallback.transcriptIdleTimeout else {
            return
        }

        recordDiagnostic("静默兜底触发")
        await finishRecording(reason: .silenceFallback)
    }

    private func recordDiagnostic(_ message: String) {
        let timestamp = diagnosticsDateFormatter.string(from: Date())
        runtimeDiagnostics.insert("[\(timestamp)] \(message)", at: 0)
        if runtimeDiagnostics.count > 10 {
            runtimeDiagnostics = Array(runtimeDiagnostics.prefix(10))
        }
        statusBarController.refresh()
    }

    private func copyRuntimeDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(runtimeDiagnostics.reversed().joined(separator: "\n"), forType: .string)
        recordDiagnostic("已复制运行诊断")
    }
}
