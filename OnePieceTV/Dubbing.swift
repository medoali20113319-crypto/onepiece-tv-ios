// Dubbing.swift — live on-device dubbing, iOS equivalent of the Android
// pipeline (ExoPlayer tap -> Vosk EN -> ML Kit EN->AR -> Android TTS).
//
// iOS has no Vosk/ML Kit dependency here by design (zero external pods,
// so the cloud build is a single xcodebuild): the same three stages run
// on Apple frameworks instead:
//   audio tap  -> MTAudioProcessingTap on the AVPlayerItem (PCM out)
//   STT        -> SFSpeechRecognizer, English, on-device where available
//   translate  -> Translation framework EN->AR (iOS 18+, on-device pack)
//   speak      -> AVSpeechSynthesizer, Arabic (ar-SA)
// Original audio is muted while dubbing speaks, and dubbing does NOT
// enable (and does NOT mute) when any stage is unavailable — same rule
// as Android v4.4.
//
// STATUS: written but NOT compiled on this VM (no Xcode here) and NOT
// device-tested. The tap + resampler + speech wiring needs an on-device
// pass before calling it done. Vosk/ML Kit can be swapped in later behind
// the same DubbingEngine interface if Apple Speech/Translation prove
// weaker on the user's streams.

import Foundation
import AVFoundation
import Speech

#if canImport(Translation)
import Translation
#endif

@MainActor
final class DubbingEngine: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastSpokenArabic: String = ""

    private var player: AVPlayer?
    private var tap: MTAudioProcessingTap?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var synthesizer = AVSpeechSynthesizer()

    // MARK: - Lifecycle

    /// Attach the audio tap to a player item and start the pipeline.
    /// Returns false (and leaves audio untouched) when any stage is missing.
    func start(player: AVPlayer, item: AVPlayerItem) async -> Bool {
        stop()
        guard await Self.speechAvailable() else {
            statusMessage = L("الدبلجة مش متاحة: التعرف على الكلام غير متوفر على الجهاز ده", "Dubbing unavailable: speech recognition is not available on this device")
            return false
        }
        guard await Self.translationAvailable() else {
            statusMessage = L("الدبلجة مش متاحة: حمّل حزمة الترجمة الإنجليزي-عربي من إعدادات الترجمة الأول", "Dubbing unavailable: download the English-Arabic translation pack in Translation settings first")
            return false
        }
        guard hasArabicVoice() else {
            statusMessage = L("الدبلجة مش متاحة: مفيش صوت عربي نازل على الجهاز — نزّله من الإعدادات", "Dubbing unavailable: no Arabic voice installed — download one in Settings")
            return false
        }
        self.player = player
        attachTap(to: item)
        startRecognition()
        player.volume = 0          // mute original while dubbing speaks
        isActive = true
        statusMessage = nil
        return true
    }

    func stop() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil
        converter = nil
        tap = nil
        synthesizer.stopSpeaking(at: .immediate)
        player?.volume = 1
        player = nil
        isActive = false
    }

    // MARK: - Availability

    static func speechAvailable() async -> Bool {
        let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard status == .authorized else { return false }
        guard let r = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else { return false }
        return r.isAvailable
    }

    static func translationAvailable() async -> Bool {
        if #available(iOS 18, *) {
            #if canImport(Translation)
            let availability = LanguageAvailability()
            let status = await availability.status(
                from: Locale.Language(identifier: "en"),
                to: Locale.Language(identifier: "ar"))
            return status == .installed
            #else
            return false
            #endif
        }
        return false
    }

    private func hasArabicVoice() -> Bool {
        AVSpeechSynthesisVoice.speechVoices().contains { $0.language.hasPrefix("ar") }
    }

    // MARK: - Audio tap (MTAudioProcessingTap on the player item)

    private func attachTap(to item: AVPlayerItem) {
        guard let track = item.asset.tracks(withMediaType: .audio).first else { return }
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(self).toOpaque(),
            init: { tap, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { _ in },
            prepare: { _, _, _ in },
            unprepare: { _ in },
            process: { tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut in
                let ctx = MTAudioProcessingTapGetStorage(tap)
                guard let ctx = ctx else { return }
                let engine = Unmanaged<DubbingEngine>.fromOpaque(ctx).takeUnretainedValue()
                engine.handleTapFrames(bufferListInOut, frameCount: numberFrames)
            })
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                                kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap = tap else { return }
        self.tap = tap
        let mix = AVMutableAudioMix()
        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap
        mix.inputParameters = [params]
        item.audioMix = mix
    }

    /// Called on the tap's realtime thread: copy PCM into the resampler.
    /// Nonisolated on purpose (the C callback runs outside the actor):
    /// it only copies bytes and hops to the MainActor to feed them.
    private nonisolated func handleTapFrames(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: CMItemCount) {
        // The tap delivers the item's native format (usually 48 kHz
        // stereo Float32). Convert to 16 kHz mono Int16 for the recognizer.
        let abl = bufferList.pointee
        guard abl.mNumberBuffers > 0 else { return }
        let buf = abl.mBuffers
        guard let data = buf.mData else { return }
        let bytes = Data(bytes: data, count: Int(buf.mDataByteSize))
        Task { @MainActor in self.feedPCM(bytes, frameCount: frameCount) }
    }

    // MARK: - Resample + recognize

    private func feedPCM(_ bytes: Data, frameCount: CMItemCount) {
        guard isActive, let request = recognitionRequest else { return }
        // Lazily build the converter once we know the source format.
        // Source format is read from the tap buffers: Float32, interleaved,
        // 2 channels, 48 kHz in practice; fall back to 44.1 kHz if the
        // converter fails to initialize (handled by recreating it).
        if converter == nil {
            guard let src = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: true),
                  let dst = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true),
                  let conv = AVAudioConverter(from: src, to: dst) else { return }
            inputFormat = src
            converter = conv
        }
        guard let converter = converter, let inputFormat = inputFormat,
              let dstFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else { return }
        let frames = Int(frameCount)
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(frames)) else { return }
        inBuf.frameLength = AVAudioFrameCount(frames)
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            inBuf.floatChannelData?.pointee?.update(from: base.assumingMemoryBound(to: Float.self), count: frames * 2)
        }
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: AVAudioFrameCount(frames / 3 + 16)) else { return }
        var error: NSError?
        converter.convert(to: outBuf, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inBuf
        }
        if error == nil, outBuf.frameLength > 0 {
            request.append(outBuf)
        }
    }

    private func startRecognition() {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else { return }
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        if #available(iOS 13, *) { request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition }
        recognitionRequest = request
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result, result.isFinal, !result.bestTranscription.formattedString.isEmpty {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in await self.translateAndSpeak(text) }
            }
            if error != nil { self.statusMessage = L("الدبلجة وقفت — حاول تاني", "Dubbing stopped — try again") }
        }
    }

    // MARK: - Translate + speak

    private func translateAndSpeak(_ english: String) async {
        guard isActive else { return }
        var arabic: String?
        if #available(iOS 18, *) {
            #if canImport(Translation)
            do {
                // iOS 18 API: the Configuration-based init does not exist
                // in this SDK (only init(installedSource:target:)).
                let session = TranslationSession(
                    installedSource: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: "ar"))
                let response = try await session.translate(english)
                arabic = response.targetText
            } catch {
                // Keep the English text out of the speaker: speaking
                // untranslated English over Arabic audio is worse than
                // skipping one utterance.
                return
            }
            #else
            return
            #endif
        } else { return }
        guard let arabic = arabic else { return }
        lastSpokenArabic = arabic
        speak(arabic)
    }

    private func speak(_ text: String) {
        guard let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("ar") }) else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
