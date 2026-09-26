import Foundation

/// UserDefaults keys for the settings. Views bind to them with @AppStorage; logic reads a `Prefs` snapshot.
/// Settings stay per device (a phone and an iPad can study differently); the cards and progress sync.
enum PrefKey {
    static let newPerDay = "newPerDay"
    static let autoSpeak = "autoSpeak"
    static let direction = "direction"
    static let vosotros = "vosotros"
    static let voiceLang = "voiceLang"
    static let tab = "tab"
    static let tense = "tense"
    static let theme = "theme"
}

struct Prefs {
    var newPerDay = 15
    var autoSpeak = true
    var direction = Direction.stage
    var vosotros = false
    var voiceLang = "es-MX"

    static var current: Prefs {
        let d = UserDefaults.standard
        var p = Prefs()
        if d.object(forKey: PrefKey.newPerDay) != nil { p.newPerDay = d.integer(forKey: PrefKey.newPerDay) }
        if d.object(forKey: PrefKey.autoSpeak) != nil { p.autoSpeak = d.bool(forKey: PrefKey.autoSpeak) }
        p.direction = Direction(rawValue: d.string(forKey: PrefKey.direction) ?? "") ?? .stage
        p.vosotros = d.bool(forKey: PrefKey.vosotros)
        p.voiceLang = d.string(forKey: PrefKey.voiceLang) ?? "es-MX"
        return p
    }
}
