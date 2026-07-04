import Foundation
import Speech
import AVFoundation

/// Push-to-talk speech input. Hold the mic → it records and transcribes ON-DEVICE (private),
/// release → the text is handed to the chat. The mind has no voice of its own yet; this is only
/// your side of the conversation, turned from speech into words it can read.
final class SpeechInput: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var status = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func begin() {
        guard !isRecording else { return }
        transcript = ""
        SFSpeechRecognizer.requestAuthorization { sp in
            AVCaptureDevice.requestAccess(for: .audio) { mic in
                DispatchQueue.main.async {
                    guard sp == .authorized, mic else {
                        self.status = (sp == .authorized ? "microphone denied" : "speech denied")
                        return
                    }
                    self.startEngine()
                }
            }
        }
    }

    @discardableResult
    func end() -> String {
        guard isRecording else { return "" }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        isRecording = false
        status = ""
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startEngine() {
        guard let recognizer, recognizer.isAvailable else { status = "recognizer unavailable"; return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { status = "audio start failed"; return }
        isRecording = true
        status = "listening…"

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                DispatchQueue.main.async { self.transcript = result.bestTranscription.formattedString }
            }
            if error != nil {
                DispatchQueue.main.async { if self.isRecording { self.status = "listening…" } }
            }
        }
    }
}
