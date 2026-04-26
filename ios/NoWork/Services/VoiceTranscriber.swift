import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Speech

/// Local speech-to-text plus server-proxied Gradium text-to-speech.
///
/// The Gradium API key never leaves the edge function. Speech input uses iOS'
/// built-in recognizer so the app does not need a long-lived third-party key on
/// the device.
@MainActor
final class VoiceTranscriber: NSObject, ObservableObject {
    @Published var transcript: String = ""
    @Published var status: String = "idle"
    @Published var isRunning: Bool = false
    @Published var error: String?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(
        locale: Locale(identifier: Locale.preferredLanguages.first ?? "en-US")
    ) ?? SFSpeechRecognizer()
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var ttsPlayer: AVAudioPlayer?
    private var speechAuthorized = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public lifecycle

    func prepare() async {
        speechAuthorized = await Self.requestSpeechPermission()
        guard speechAuthorized else {
            status = "speech disabled"
            error = "speech recognition denied — enable it in Settings"
            return
        }
        guard speechRecognizer?.isAvailable == true else {
            status = "speech unavailable"
            error = "speech recognition is unavailable right now"
            return
        }
        status = "ready — tap to talk"
    }

    func start() async {
        guard !isRunning else { return }
        if !speechAuthorized {
            await prepare()
            guard speechAuthorized else { return }
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            status = "speech unavailable"
            error = "speech recognition is unavailable right now"
            return
        }

        error = nil
        transcript = ""
        status = "asking mic permission..."

        let micGranted = await Self.requestMicPermission()
        guard micGranted else {
            error = "microphone access denied — enable it in Settings"
            status = "denied"
            return
        }

        do {
            try configureRecordingSession()
            try startRecognition(with: speechRecognizer)
            status = "listening"
            isRunning = true
        } catch {
            await stop()
            self.error = error.localizedDescription
            status = "error"
        }
    }

    func stop() async {
        guard isRunning || audioEngine.isRunning else { return }
        isRunning = false
        status = "stopping..."

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionRequest = nil

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
        status = transcript.isEmpty ? "stopped" : "got it"
    }

    // MARK: - TTS playback

    func speak(_ text: String, voiceId: String = "YTpq7expH9539ERJ") async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let data = try? await EdgeFunctions.shared.voiceSpeech(
            text: trimmed,
            voiceId: voiceId
        ), playAudio(data) {
            return
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    // MARK: - Internals

    private func configureRecordingSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .record,
            mode: .measurement,
            options: [.duckOthers]
        )
        try session.setActive(true, options: [.notifyOthersOnDeactivation])
    }

    private func startRecognition(with recognizer: SFSpeechRecognizer) throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let input = audioEngine.inputNode
        let recordingFormat = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) {
            buffer,
            _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) {
            [weak self] result,
            recognitionError in
            let bestText = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let errorMessage = recognitionError?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let bestText, !bestText.isEmpty {
                    self.transcript = bestText
                }
                if isFinal {
                    self.status = self.transcript.isEmpty ? "stopped" : "got it"
                }
                if let errorMessage, self.isRunning {
                    self.error = errorMessage
                    self.status = "error"
                }
            }
        }
    }

    private func playAudio(_ data: Data) -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: []
            )
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: data)
            ttsPlayer = player
            player.prepareToPlay()
            return player.play()
        } catch {
            return false
        }
    }

    private static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private static func requestMicPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

extension VoiceTranscriber: AVSpeechSynthesizerDelegate {}
