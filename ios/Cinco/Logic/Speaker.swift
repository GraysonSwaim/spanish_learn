import AVFoundation
import AudioToolbox

/// Says Spanish words with the best iOS voice installed for the accent. Settings › Accessibility › Spoken Content › Voices
/// can download Enhanced and Premium voices, which sound far better than the default.
///
/// Speech goes through a presence boost for clarity, then a limiter with pre-gain, so words play
/// louder than the phone's plain media volume without clipping.
@MainActor
final class Speaker: NSObject {
    static let shared = Speaker()

    private let synth = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 2)
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    /// Everything is converted to this before it reaches the chain.
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    /// Bumped on every speak/stop so late speech buffers from an earlier word are dropped.
    private var generation = 0
    private var speechArrived = false

    /// Into the limiter, in dB. Its ceiling is -3 dBFS, so this sets how hard quiet syllables are lifted,
    /// not the peak level.
    private static let preGain: AudioUnitParameterValue = 10

    override private init() {
        super.init()
        // Full media volume, like a music app, rather than the quiet "ambient" default.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])

        // Lift the consonants and trim the low rumble.
        let presence = eq.bands[0]
        presence.filterType = .parametric
        presence.frequency = 3_500
        presence.bandwidth = 1.5
        presence.gain = 4
        presence.bypass = false
        let lowCut = eq.bands[1]
        lowCut.filterType = .highPass
        lowCut.frequency = 90
        lowCut.bypass = false

        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, Self.preGain, 0)

        engine.attach(node)
        engine.attach(eq)
        engine.attach(limiter)
        engine.connect(node, to: eq, format: format)
        engine.connect(eq, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
    }

    func speak(_ text: String, lang: String) {
        let t = TextMatch.spokenText(text)
        guard !t.isEmpty else { return }
        stop()
        try? AVAudioSession.sharedInstance().setActive(true)
        guard startEngine() else { return fallbackSpeak(t, lang: lang) }
        let u = utterance(t, lang: lang)
        let gen = generation
        speechArrived = false
        synth.write(u) { [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return }
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                self.speechArrived = true
                self.play(pcm)
            }
        }
        // Some voices never hand back audio through write(); speak them directly instead.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self, self.generation == gen, !self.speechArrived else { return }
            self.generation += 1   // drop any buffers that turn up after all
            self.synth.stopSpeaking(at: .immediate)
            self.synth.speak(self.utterance(t, lang: lang))
        }
    }

    func stop() {
        generation += 1
        node.stop()
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    private func startEngine() -> Bool {
        if engine.isRunning { return true }
        do { try engine.start(); return true } catch { return false }
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        guard let converted = convert(buffer) else { return }
        // The engine stops itself on route changes (headphones, calls), so check again.
        guard startEngine() else { return }
        node.scheduleBuffer(converted)
        if !node.isPlaying { node.play() }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
    }

    /// Only if the engine can't start: play plainly rather than not at all.
    private func fallbackSpeak(_ t: String, lang: String) {
        synth.speak(utterance(t, lang: lang))
    }

    private func utterance(_ t: String, lang: String) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: t)
        u.voice = Self.bestVoice(lang)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        return u
    }

    /// Premium over Enhanced over default, for the exact accent if possible, else any Spanish.
    static func bestVoice(_ lang: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let rank = { (v: AVSpeechSynthesisVoice) -> Int in
            switch v.quality {
            case .premium: 3
            case .enhanced: 2
            default: 1
            }
        }
        let exact = voices.filter { $0.language == lang }
        let pool = exact.isEmpty ? voices.filter { $0.language.hasPrefix("es") } : exact
        return pool.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: lang)
    }
}
