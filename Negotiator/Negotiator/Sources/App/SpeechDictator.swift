import Foundation
import Speech
import AVFoundation

// Live speech-to-text for the composer. Wraps SFSpeechRecognizer + AVAudioEngine: the mic streams
// audio to the recognizer and partial transcripts flow back as you speak (onText). Tap to start,
// tap to stop; the recognized text fills the draft for review before sending.
@MainActor
final class SpeechDictator: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var errorText: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onText: ((String) -> Void)?

    var isSupported: Bool { recognizer != nil }

    // Tap entry point: ask for permission the first time, then begin streaming.
    func start(onText: @escaping (String) -> Void) {
        guard !isRecording else { return }
        self.onText = onText
        errorText = nil
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.errorText = "Allow Speech Recognition in Settings to talk."
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.errorText = "Allow Microphone access in Settings to talk."
                            return
                        }
                        self.beginSession()
                    }
                }
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else {
            errorText = "Speech recognition isn\u{2019}t available right now."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorText = "Couldn\u{2019}t start the microphone."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        // The tap runs on the audio thread; capture `request` directly (never `self`) so we don't
        // cross the main-actor boundary from a realtime callback.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorText = "Couldn\u{2019}t start the microphone."
            audioEngine.inputNode.removeTap(onBus: 0)
            self.request = nil
            return
        }

        isRecording = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.onText?(result.bestTranscription.formattedString)
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stop()
                }
            }
        }
    }
}
