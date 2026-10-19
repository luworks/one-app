#if os(iOS)
import AVFoundation
import Speech
import SwiftUI

/// A session driver. Scripted implementations belong in Development and must never touch system audio.
@MainActor
package protocol SpeechInputDriving: AnyObject {
    func start(onTranscript: @escaping @MainActor (String) -> Void,
               onState: @escaping @MainActor (VoiceInput.State) -> Void) async
    func stop()
}

@MainActor
@Observable
package final class VoiceInput {
    package enum State: Equatable { case idle, listening, denied, unavailable }
    package private(set) var state: State = .idle
    package private(set) var transcript = ""
    @ObservationIgnored private let driver: any SpeechInputDriving
    @ObservationIgnored private var generation = 0

    package init(driver: any SpeechInputDriving) { self.driver = driver }
    package func toggle() async {
        if state == .listening { stop() } else { await start() }
    }
    package func start() async {
        generation += 1
        let token = generation
        transcript = ""
        await driver.start(onTranscript: { [weak self] text in
            guard let self, self.generation == token else { return }
            self.transcript = text
        }, onState: { [weak self] state in
            guard let self, self.generation == token else { return }
            self.state = state
        })
    }
    package func stop() {
        generation += 1
        driver.stop()
        if state == .listening { state = .idle }
    }
}

/// Construction and stop-before-start never initialize AVAudioEngine, recognition or AVAudioSession.
@MainActor
package final class LiveSpeechInputDriver: SpeechInputDriving {
    private let locale: Locale
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onTranscript: (@MainActor (String) -> Void)?
    private var onState: (@MainActor (VoiceInput.State) -> Void)?
    private var sessionActive = false
    private var tapped = false
    private var generation = 0

    package init(locale: Locale) { self.locale = locale }

    package func start(onTranscript: @escaping @MainActor (String) -> Void,
                       onState: @escaping @MainActor (VoiceInput.State) -> Void) async {
        stop()
        self.onTranscript = onTranscript
        self.onState = onState
        generation += 1
        let token = generation
        #if targetEnvironment(simulator)
        // CoreAudio input deadlocks in the simulator; dictation is device-only.
        onState(.unavailable)
        #else
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard generation == token, !Task.isCancelled else { return }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard generation == token, !Task.isCancelled else { return }
        guard speech == .authorized, mic else { onState(.denied); return }
        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { onState(.unavailable); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            sessionActive = true
            let engine = AVAudioEngine()
            self.engine = engine
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { stop(); onState(.unavailable); return }
            var tapError: NSError?
            guard input.__installTap(onBus: 0, bufferSize: 1024, format: format, error: &tapError, block: Self.tapBlock(request)) else {
                throw tapError ?? NSError(domain: "Today.AudioInput", code: 1)
            }
            tapped = true
            engine.prepare()
            try engine.start()
            onState(.listening)
            task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(self, token: token))
        } catch {
            stop()
            onState(.unavailable)
        }
        #endif
    }

    nonisolated private static func tapBlock(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }
    nonisolated private static func resultHandler(_ owner: LiveSpeechInputDriver, token: Int) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak owner] result, error in
            let text = result?.bestTranscription.formattedString
            let done = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                guard let owner, owner.generation == token else { return }
                if let text { owner.onTranscript?(text) }
                if done { owner.onState?(.idle); owner.stop() }
            }
        }
    }
    package func stop() {
        generation += 1
        engine?.stop()
        if tapped { engine?.inputNode.removeTap(onBus: 0) }
        tapped = false
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil; engine = nil
        onTranscript = nil; onState = nil
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
    }
}
#endif
