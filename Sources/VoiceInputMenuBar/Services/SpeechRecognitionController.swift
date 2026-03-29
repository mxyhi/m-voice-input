import AVFoundation
import Foundation
import Speech
import VoiceInputCore

final class SpeechRecognitionController: @unchecked Sendable {
    private let onTranscript: @Sendable (String) -> Void
    private let onWaveform: @Sendable ([Double]) -> Void

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var waveformProcessor = WaveformLevelProcessor()
    private var latestTranscript = ""
    private var stopContinuation: CheckedContinuation<String, Never>?
    private var stopTimeoutTask: Task<Void, Never>?
    private var didRequestStop = false

    init(
        onTranscript: @escaping @Sendable (String) -> Void,
        onWaveform: @escaping @Sendable ([Double]) -> Void
    ) {
        self.onTranscript = onTranscript
        self.onWaveform = onWaveform
    }

    func start(localeIdentifier: String) throws {
        cleanup()

        didRequestStop = false
        latestTranscript = ""
        waveformProcessor = WaveformLevelProcessor()

        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) else {
            throw SpeechRecognitionError.unsupportedLocale
        }

        self.speechRecognizer = speechRecognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else {
                return
            }

            if let result {
                latestTranscript = result.bestTranscription.formattedString
                onTranscript(latestTranscript)

                if result.isFinal {
                    finishStop(with: latestTranscript)
                }
            }

            if error != nil, didRequestStop {
                finishStop(with: latestTranscript)
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, let recognitionRequest else {
                return
            }

            recognitionRequest.append(buffer)
            let rms = Self.rmsValue(for: buffer)
            let levels = waveformProcessor.process(rms: Double(rms))
            onWaveform(levels)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() async -> String {
        guard audioEngine.isRunning || recognitionTask != nil else {
            return latestTranscript
        }

        didRequestStop = true
        recognitionRequest?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        return await withCheckedContinuation { continuation in
            stopContinuation = continuation
            stopTimeoutTask?.cancel()
            stopTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                self?.finishStop(with: self?.latestTranscript ?? "")
            }
        }
    }

    private func finishStop(with transcript: String) {
        stopTimeoutTask?.cancel()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        stopContinuation?.resume(returning: transcript)
        stopContinuation = nil
    }

    private func cleanup() {
        stopTimeoutTask?.cancel()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        stopContinuation?.resume(returning: latestTranscript)
        stopContinuation = nil
    }

    private static func rmsValue(for buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else {
            return 0
        }

        let channel = channelData[0]
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return 0
        }

        var sum: Float = 0
        for index in 0..<frameLength {
            let sample = channel[index]
            sum += sample * sample
        }

        return sqrt(sum / Float(frameLength))
    }
}

enum SpeechRecognitionError: Error {
    case unsupportedLocale
}
