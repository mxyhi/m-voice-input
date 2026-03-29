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
        permissionCoordinator.refreshAccessibility(prompt: false)
        statusBarController.refresh()
        fnMonitor.start()
        updatePermissionSummary()
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

    private func updatePermissionSummary() {
        let inputMonitoringGranted = fnMonitor.isActive
        let summary = permissionCoordinator.makeSummary(inputMonitoringGranted: inputMonitoringGranted)
        statusBarController.updatePermissionSummary(summary)
    }

    private func beginRecording() async {
        guard !isRecording else {
            return
        }

        let speechGranted = await permissionCoordinator.requestSpeechRecognitionIfNeeded()
        let microphoneGranted = await permissionCoordinator.requestMicrophoneIfNeeded()
        permissionCoordinator.refreshAccessibility(prompt: false)
        updatePermissionSummary()

        guard speechGranted, microphoneGranted else {
            overlayController.show(message: "请先授予麦克风和语音识别权限", levels: .idle)
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
