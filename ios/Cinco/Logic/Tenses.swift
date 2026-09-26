import Foundation

nonisolated enum Mood: String, CaseIterable {
    case ind, sub, imp

    var name: String {
        switch self {
        case .ind: "Indicativo"
        case .sub: "Subjuntivo"
        case .imp: "Imperativo"
        }
    }
}

/// One tense a verb can carry. `key` is the CSV column name, and the order of `Tense.all`
/// is the column order of a headerless file, same as the web app.
nonisolated struct Tense: Identifiable, Hashable {
    let key: String
    let name: String
    let short: String?
    let mood: Mood
    /// Subjunctive persons read "que yo…".
    var que: Bool { mood == .sub }
    /// Commands have no yo.
    var imperative: Bool { mood == .imp }
    var id: String { key }
    var label: String { short ?? name }

    static let all: [Tense] = [
        Tense(key: "presente", name: "Presente", short: nil, mood: .ind),
        Tense(key: "preterito", name: "Pretérito", short: nil, mood: .ind),
        Tense(key: "imperfecto", name: "Imperfecto", short: nil, mood: .ind),
        Tense(key: "futuro", name: "Futuro", short: nil, mood: .ind),
        Tense(key: "condicional", name: "Condicional", short: nil, mood: .ind),
        Tense(key: "subjuntivo", name: "Presente de subjuntivo", short: "Presente", mood: .sub),
        Tense(key: "subj_imperfecto", name: "Imperfecto de subjuntivo", short: "Imperfecto", mood: .sub),
        Tense(key: "imperativo", name: "Imperativo afirmativo", short: "Afirmativo", mood: .imp),
        Tense(key: "imperativo_negativo", name: "Imperativo negativo", short: "Negativo", mood: .imp),
        Tense(key: "perfecto", name: "Pretérito perfecto", short: "Perfecto", mood: .ind),
        Tense(key: "pluscuamperfecto", name: "Pluscuamperfecto", short: "Pluscuamp.", mood: .ind),
        Tense(key: "futuro_perfecto", name: "Futuro perfecto", short: "Fut. perfecto", mood: .ind),
        Tense(key: "condicional_perfecto", name: "Condicional perfecto", short: "Cond. perfecto", mood: .ind),
        Tense(key: "subj_perfecto", name: "Perfecto de subjuntivo", short: "Perfecto", mood: .sub),
        Tense(key: "subj_pluscuamperfecto", name: "Pluscuamperfecto de subjuntivo", short: "Pluscuamp.", mood: .sub),
    ]

    private static let byKey = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    static func named(_ key: String) -> Tense? { byKey[key] }
    static func index(of key: String) -> Int { all.firstIndex { $0.key == key } ?? all.count }

    /// The Aleatorio pseudo-tense in the Conjugación tab.
    static let random = "random"
}

/// Persons in the order of every tense column: yo|tú|él|nosotros|vosotros|ellos.
nonisolated enum Person {
    static let names = ["yo", "tú", "él / ella / usted", "nosotros", "vosotros", "ellos / ellas / ustedes"]
    static let imperative = ["", "tú", "usted", "nosotros", "vosotros", "ustedes"]
    static let pronouns: [[String]] = [["yo"], ["tú", "tu", "vos"], ["él", "el", "ella", "usted"],
                                       ["nosotros", "nosotras"], ["vosotros", "vosotras"], ["ellos", "ellas", "ustedes"]]
    static let vosotros = 4

    static func label(_ p: Int, _ tense: String) -> String {
        guard let t = Tense.named(tense) else { return names[p] }
        if t.imperative { return imperative[p] }
        return (t.que ? "que " : "") + names[p]
    }
}
