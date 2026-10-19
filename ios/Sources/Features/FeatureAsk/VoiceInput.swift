#if os(iOS)
import AVFoundation
import Speech
import SwiftUI

/// Push-to-talk dictation for the AI input (Speech framework). Transcribes live into the draft;
/// the user still sends it, so nothing happens without a tap.
@MainActor
@Observable
final class VoiceInput {
    enum State: Equatable { case idle, listening, denied, unavailable }

    private(set) var state: State = .idle
    private(set) var transcript = ""

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    func toggle() async {
        if state == .listening { stop() } else { await start() }
    }

    func start() async {
        transcript = ""
        #if targetEnvironment(simulator)
        // CoreAudio input deadlocks in the simulator ("RPC timeout"); dictation is device-only.
        state = .unavailable
        #else
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard speech == .authorized, mic else { state = .denied; return }
        guard let recognizer, recognizer.isAvailable else { state = .unavailable; return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { state = .unavailable; return }
            var tapError: NSError?
            guard input.__installTap(onBus: 0, bufferSize: 1024, format: format, error: &tapError, block: Self.tapBlock(request)) else {
                throw tapError ?? NSError(domain: "Today.AudioInput", code: 1)
            }
            engine.prepare()
            try engine.start()
            state = .listening

            task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(self))
        } catch {
            stop()
            state = .unavailable
        }
        #endif
    }

    // Audio and speech callbacks arrive on background threads, so they must not be main-actor closures.
    nonisolated private static func tapBlock(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    nonisolated private static func resultHandler(_ owner: VoiceInput) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak owner] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                guard let owner else { return }
                if let text { owner.transcript = text }
                if done { owner.stop() }
            }
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if state == .listening { state = .idle }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

#endif
