import AVFoundation

/// Says Spanish words: the Mac recording from audio/es-MX when there is one (Latin American accent only),
/// otherwise the best iOS voice installed for the accent. Settings › Accessibility › Spoken Content › Voices
/// can download Enhanced and Premium voices, which sound far better than the default.
@MainActor
final class Speaker: NSObject {
    static let shared = Speaker()

    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private let recordingLang = "es-MX"

    override private init() {
        super.init()
        // Full media volume, like a music app, rather than the quiet "ambient" default.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    func speak(_ text: String, lang: String) {
        let t = TextMatch.spokenText(text)
        guard !t.isEmpty else { return }
        stop()
        try? AVAudioSession.sharedInstance().setActive(true)
        if lang == recordingLang, let url = recording(for: t), let p = try? AVAudioPlayer(contentsOf: url) {
            player = p
            p.play()
            return
        }
        let u = AVSpeechUtterance(string: t)
        u.voice = Self.bestVoice(lang)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synth.speak(u)
    }

    func stop() {
        player?.stop()
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    /// Recordings are named hash(strip(text)), the same key the web app uses.
    private func recording(for text: String) -> URL? {
        Bundle.main.url(forResource: TextMatch.cardID(text), withExtension: "m4a", subdirectory: recordingLang)
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
