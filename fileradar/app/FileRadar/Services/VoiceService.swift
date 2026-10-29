import AVFoundation
import Combine
import Speech

// MARK: - VoiceService
//
// Voice input and output for the FileRadar in-app chat.
//
// Wired by the chat UI (the chat-UI sibling owns that wiring); this file
// provides only the service the chat UI calls. It makes no network calls
// of its own, sends no analytics, and never logs transcripts or audio.
//
// API (shared contract with the chat UI — use these names exactly):
//   final class VoiceService: ObservableObject
//   @Published var isListening: Bool        // true only while the audio
//                                           // engine is actually running;
//                                           // drives the mic indicator
//   @Published var isSpeaking: Bool         // tracks the speech
//                                           // synthesizer delegate state
//   @Published var handsFree: Bool          // false = push-to-talk,
//                                           // true = continuous listening
//   @Published var lastTranscript: String   // live partial text, then the
//                                           // latest final transcript
//   @Published var lastError: String?       // addition to the contract:
//                                           // generic, UI-showable error
//                                           // string; nil when clear
//   var onTranscript: ((String) -> Void)?   // fired ONLY for final
//                                           // transcripts; the chat UI
//                                           // sends each one as a user
//                                           // message, routed through the
//                                           // same tool layer as typed
//                                           // text (e.g. "find screenshots
//                                           // from last week" becomes a
//                                           // chat message that can
//                                           // trigger searchFiles)
//   func startListening()                   // push-to-talk: chat UI calls
//                                           // this on press, stopListening
//                                           // on release
//   func stopListening()                    // ends listening (and, in
//                                           // hands-free mode, ends the
//                                           // continuous session)
//   func speak(_ text: String)              // speaks the text aloud
//   func stopSpeaking()                     // stops speech immediately
//
// Push-to-talk vs hands-free:
//   handsFree == false: one utterance per startListening()/stopListening()
//   pair. Releasing (stopListening) ends the session even if no final
//   transcript arrived yet.
//   handsFree == true: after each final transcript is delivered, a fresh
//   recognition task starts automatically and listening continues until
//   stopListening() is called. Toggling handsFree off mid-session takes
//   effect at the next final transcript: that transcript is still
//   delivered, then listening stops instead of restarting.
//
// Transcripts:
//   Partial results update lastTranscript live but NEVER fire
//   onTranscript. Only a final result (isFinal == true, non-empty after
//   trimming) is published in lastTranscript AND delivered via
//   onTranscript, exactly once.
//
// Audio is NEVER stored:
//   Buffers from the microphone are appended to an in-memory recognition
//   request and processed in memory only. There are no file writes and no
//   recordings anywhere in this service, in either mode.
//
// Recognition routing:
//   On-device recognition is preferred: requiresOnDeviceRecognition is
//   set whenever the recognizer reports that it supports it. When the
//   recognizer does not support on-device recognition, this service falls
//   back to the system's default recognition path for that recognizer.
//   No FileRadar server-side transcription is wired in this service —
//   there is no FileRadar transcription endpoint, and this service sends
//   audio to no FileRadar server. The fallback is purely the Apple
//   Speech framework's own behaviour when on-device recognition is
//   unavailable on the device.
//
// Permissions — REQUIRED Info.plist keys (owned by the auth sibling;
// this service does not edit Info.plist):
//   NSMicrophoneUsageDescription
//     Suggested string: "FileRadar uses the microphone so you can search
//     and control the app by voice."
//   NSSpeechRecognitionUsageDescription
//     Suggested string: "FileRadar uses speech recognition to turn your
//     spoken words into searches and commands."
//   startListening() requests both authorizations through the system
//   flow (speech-recognition authorization AND microphone access) when
//   their status is not yet determined, and proceeds only when both are
//   granted. If either is denied or restricted, listening does not start
//   and lastError is set to a generic message only — no permission
//   internals are leaked to the UI beyond:
//     "Microphone or speech recognition permission is needed."
//   Recognition-task failures likewise surface only as the generic
//   string "Speech recognition failed. Please try again."
//
// Speech-output preferences:
//   The synthesizer voice identifier and rate are non-secret user
//   preferences stored in UserDefaults ONLY (never tokens, never
//   credentials):
//     "voiceService.voiceIdentifier" (String, empty = system default)
//     "voiceService.speechRate"       (Float, clamped to 0.0...1.0,
//                                      default AVSpeechUtterance
//                                      default rate)
//   Changing voiceIdentifier or speechRate persists immediately and
//   applies to the next speak(_:) call.
//
// "Listening…" state discipline:
//   isListening is set to true only after the audio engine has actually
//   started, and back to false as soon as the engine stops, the tap is
//   removed, or an error ends the session — never merely because
//   startListening() was called. The chat UI's mic indicator binds to it.
//
// Cancellation / robustness:
//   stopListening() mid-utterance is safe: it finishes/cancels the
//   recognition task, removes the audio tap, and stops the engine, in an
//   order that cannot double-remove the tap or resume a finished task.
//   Stale task callbacks (from a previous session) are ignored via a
//   session token, so a late result can never fire onTranscript after
//   listening stopped. speak(_:) with empty text is a no-op, and a new
//   speak(_:) call stops any speech already in progress first.

final class VoiceService: NSObject, ObservableObject {

    // MARK: - Shared contract

    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var handsFree = false
    @Published var lastTranscript = ""
    @Published var lastError: String?

    /// Fired exactly once per final transcript. Partial transcripts never
    /// fire this. Set by the chat UI; invoked on the main thread.
    var onTranscript: ((String) -> Void)?

    // MARK: - Speech-output preferences (UserDefaults only)

    private static let voiceIdentifierKey = "voiceService.voiceIdentifier"
    private static let speechRateKey = "voiceService.speechRate"

    /// Identifier of the AVSpeechSynthesisVoice to use; empty means the
    /// system default voice for the current locale.
    var voiceIdentifier: String {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: Self.voiceIdentifierKey) }
    }

    /// Speech rate, clamped to AVSpeechUtterance's 0.0...1.0 range.
    var speechRate: Float {
        didSet {
            let clamped = min(max(speechRate, AVSpeechUtteranceMinimumSpeechRate),
                              AVSpeechUtteranceMaximumSpeechRate)
            if clamped != speechRate { speechRate = clamped }
            UserDefaults.standard.set(speechRate, forKey: Self.speechRateKey)
        }
    }

    // MARK: - Private state

    private static let permissionErrorMessage =
        "Microphone or speech recognition permission is needed."
    private static let recognitionErrorMessage =
        "Speech recognition failed. Please try again."

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var shouldKeepListening = false
    private var sessionToken = 0

    override init() {
        self.voiceIdentifier = UserDefaults.standard.string(forKey: Self.voiceIdentifierKey) ?? ""
        let savedRate = UserDefaults.standard.object(forKey: Self.speechRateKey) as? Float
        self.speechRate = savedRate ?? AVSpeechUtteranceDefaultSpeechRate
        super.init()
        synthesizer.delegate = self
    }

    deinit {
        // Best-effort teardown; published-state updates are skipped here
        // because the object is being destroyed.
        recognitionTask?.cancel()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Listening

    /// Starts listening. Requests speech-recognition and microphone
    /// authorization through the system flow if not yet determined, and
    /// proceeds only when both are granted. Safe to call while already
    /// listening: it is a no-op in that case.
    func startListening() {
        guard !isListening else { return }
        lastError = nil
        shouldKeepListening = true
        sessionToken += 1
        let token = sessionToken

        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.sessionToken == token, self.shouldKeepListening else { return }
                guard speechStatus == .authorized else {
                    self.failListening(with: Self.permissionErrorMessage, token: token)
                    return
                }
                self.requestMicrophoneAccess(token: token)
            }
        }
    }

    private func requestMicrophoneAccess(token: Int) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginAudioSession(token: token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async {
                    guard self.sessionToken == token, self.shouldKeepListening else { return }
                    if granted {
                        self.beginAudioSession(token: token)
                    } else {
                        self.failListening(with: Self.permissionErrorMessage, token: token)
                    }
                }
            }
        default:
            failListening(with: Self.permissionErrorMessage, token: token)
        }
    }

    private func beginAudioSession(token: Int) {
        guard shouldKeepListening, sessionToken == token else { return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            failListening(with: Self.recognitionErrorMessage, token: token)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        // Otherwise the system's default recognition path is used; no
        // FileRadar server-side transcription is wired (see header).
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        if !tapInstalled {
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }
            tapInstalled = true
        }

        do {
            try audioEngine.start()
        } catch {
            teardownAudio()
            failListening(with: Self.recognitionErrorMessage, token: token)
            return
        }

        // The engine is actually running now — only now is the mic
        // indicator state allowed to turn on.
        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.handleRecognition(result: result, error: error, token: token)
            }
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?,
                                   error: Error?,
                                   token: Int) {
        // Ignore callbacks from a session that has already ended.
        guard sessionToken == token, shouldKeepListening || isListening else { return }

        if let result {
            let text = result.bestTranscription.formattedString
            if result.isFinal {
                let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !finalText.isEmpty else { return }
                lastTranscript = finalText
                onTranscript?(finalText)
                if handsFree && shouldKeepListening {
                    // Continuous mode: end this task and start a fresh
                    // one on the still-running engine.
                    restartRecognitionTask(token: token)
                } else {
                    stopListening()
                }
            } else {
                // Partial: live display only, never delivered.
                lastTranscript = text
            }
            return
        }

        if error != nil {
            // A task error ends this session with a generic message.
            // Cancellation caused by our own stopListening() is already
            // filtered above via shouldKeepListening/isListening, and
            // stopListening() clears state before this can surface.
            stopListening()
            lastError = Self.recognitionErrorMessage
        }
    }

    /// Ends the current recognition task (without stopping the audio
    /// engine or removing the tap) and starts a fresh task on the same
    /// running engine, for hands-free continuation.
    private func restartRecognitionTask(token: Int) {
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            stopListening()
            lastError = Self.recognitionErrorMessage
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.handleRecognition(result: result, error: error, token: token)
            }
        }
    }

    /// Stops listening. Safe to call mid-utterance, repeatedly, or when
    /// not listening. Removes the audio tap exactly once, stops the
    /// engine, and finishes the task so no late callback can fire.
    func stopListening() {
        shouldKeepListening = false
        sessionToken += 1
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        teardownAudio()
        isListening = false
    }

    private func teardownAudio() {
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    private func failListening(with message: String, token: Int) {
        guard sessionToken == token else { return }
        shouldKeepListening = false
        teardownAudio()
        isListening = false
        lastError = message
    }

    // MARK: - Speaking

    /// Speaks the text aloud. Empty text is a no-op. Any speech already
    /// in progress is stopped first, so a new message replaces the old
    /// one rather than queueing behind it.
    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        if !voiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        }
        utterance.rate = speechRate
        synthesizer.speak(utterance)
        // isSpeaking is confirmed by the synthesizer delegate (didStart);
        // setting it here as well keeps the state truthful if the
        // delegate callback is delayed, and didCancel/didFinish correct
        // it when speech actually ends.
        isSpeaking = true
    }

    /// Stops speech immediately. The delegate's didCancel callback also
    /// clears isSpeaking; setting it here makes the stop immediate from
    /// the UI's point of view.
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}
