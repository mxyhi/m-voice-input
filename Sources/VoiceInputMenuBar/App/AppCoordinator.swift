import AppKit
import Foundation
import Speech
import VoiceInputCore

@MainActor
final class AppCoordinator {
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
                overlayController.updateTranscript(transcript)
            }
        },
        onWaveform: { [weak self] levels in
            Task { @MainActor [weak self] in
                self?.overlayController.updateWaveform(levels)
            }
        }
    )

    private lazy var fnMonitor = FnKeyMonitor(
        onPress: { [weak self] in
            Task { @MainActor [weak self] in
                await self?.beginRecording()
            }
        },
        onRelease: { [weak self] in
            Task { @MainActor [weak self] in
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
        onQuit: {
            NSApplication.shared.terminate(nil)
        }
    )

    private var settings: AppSettings
    private var latestTranscript = ""
    private var isRecording = false

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

        let permissionSnapshot = await permissionCoordinator.requestMissingPermissions()
        _ = fnMonitor.restart()
        let refreshedSnapshot = updatePermissionSummary()

        guard permissionSnapshot.isReady && refreshedSnapshot.isReady else {
            permissionCenterWindowController.present()
            overlayController.show(message: "请先完成权限授权", levels: .idle)
            overlayController.dismiss(after: 1.4)
            return
        }

        do {
            latestTranscript = ""
            overlayController.show(message: "开始说话…", levels: .idle)
            try speechController.start(localeIdentifier: settings.selectedLanguage.localeIdentifier)
            isRecording = true
        } catch {
            overlayController.show(message: "录音启动失败", levels: .idle)
            overlayController.dismiss(after: 1.2)
        }
    }

    private func finishRecording() async {
        guard isRecording else {
            return
        }

        isRecording = false
        let transcript = await speechController.stop()
        latestTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !latestTranscript.isEmpty else {
            overlayController.show(message: "未识别到语音", levels: .idle)
            overlayController.dismiss(after: 0.9)
            return
        }

        let finalText: String
        if settings.llm.isConfigured {
            overlayController.show(message: "Refining...", levels: .idle)
            finalText = await refineTranscriptIfPossible(latestTranscript)
        } else {
            finalText = latestTranscript
        }

        overlayController.show(message: finalText, levels: .idle)

        do {
            try await textInjectionService.inject(text: finalText)
        } catch {
            overlayController.show(message: "文本注入失败", levels: .idle)
            overlayController.dismiss(after: 1.2)
            return
        }

        overlayController.dismiss(after: 0.24)
    }

    private func refineTranscriptIfPossible(_ transcript: String) async -> String {
        do {
            return try await llmRefinementService.refine(transcript: transcript, settings: settings.llm)
        } catch {
            return transcript
        }
    }
}
