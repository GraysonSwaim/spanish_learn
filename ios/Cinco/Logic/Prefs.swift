import Foundation

/// UserDefaults keys for the settings. Views bind to them with @AppStorage; logic reads a `Prefs` snapshot.
/// Settings stay per device (a phone and an iPad can study differently); the cards and progress sync.
enum PrefKey {
    static let stageCap = "stageCap"
    /// Set once stages 1 and 2 have been trimmed to the cap (`Scheduler.trim`).
    static let trimmed = "pipelineTrimmed"
    static let autoSpeak = "autoSpeak"
    static let direction = "direction"
    static let vosotros = "vosotros"
    static let voiceLang = "voiceLang"
    static let tab = "tab"
    static let tense = "tense"
    static let theme = "theme"
    static let askMnemonics = "askMnemonics"
    /// Example sentences from Claude (`Examples`).
    static let examples = "exampleSentences"
}

struct Prefs {
    var stageCap = Scheduler.defaultCap
    var autoSpeak = true
    var direction = Direction.stage
    var vosotros = false
    var voiceLang = "es-MX"
    var askMnemonics = true

    static var current: Prefs {
        let d = UserDefaults.standard
        var p = Prefs()
        if d.object(forKey: PrefKey.stageCap) != nil { p.stageCap = max(1, d.integer(forKey: PrefKey.stageCap)) }
        if d.object(forKey: PrefKey.autoSpeak) != nil { p.autoSpeak = d.bool(forKey: PrefKey.autoSpeak) }
        p.direction = Direction(rawValue: d.string(forKey: PrefKey.direction) ?? "") ?? .stage
        p.vosotros = d.bool(forKey: PrefKey.vosotros)
        p.voiceLang = d.string(forKey: PrefKey.voiceLang) ?? "es-MX"
        if d.object(forKey: PrefKey.askMnemonics) != nil { p.askMnemonics = d.bool(forKey: PrefKey.askMnemonics) }
        return p
    }
}
