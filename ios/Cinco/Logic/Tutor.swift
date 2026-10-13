import Foundation

/// Claude for Lecturas: checks a reading's translations and drafts cards from the words marked in it. The app never holds
/// the API key; it asks the proxy in `proxy/`, which holds the key, writes the prompts and keeps each phone to a daily
/// allowance.
enum Tutor {
    /// The deployed proxy, from `wrangler deploy`. Empty leaves Lecturas without Claude.
    private static let deployed = "https://choca-cinco-tutor.goswaim100.workers.dev"

    static var base: URL? {
        #if DEBUG
        // -tutorURL http://localhost:8787: a proxy running on this Mac (`npm run dev` in proxy/).
        if let i = CommandLine.arguments.firstIndex(of: "-tutorURL"), i + 1 < CommandLine.arguments.count {
            return URL(string: CommandLine.arguments[i + 1])
        }
        #endif
        return deployed.isEmpty ? nil : URL(string: deployed)
    }

    static var available: Bool { demo || base != nil }

    /// DEBUG `-tutorDemo`: canned answers after a short wait, so the screens can be tried without the proxy.
    private static var demo: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-tutorDemo")
        #else
        false
        #endif
    }

    // MARK: answers

    nonisolated struct LineCheck: Codable, Equatable {
        /// "good", "close", "off" or "blank".
        var verdict: String
        var comment: String
        /// A natural translation (es-en), or the learner's Spanish set right (en-es).
        var better: String
    }

    nonisolated struct Missed: Codable, Equatable, Hashable {
        var line: Int
        var text: String
    }

    nonisolated struct Check: Codable, Equatable {
        var lines: [LineCheck]
        var missed: [Missed]
        var notes: [String]
    }

    nonisolated struct Gloss: Codable, Equatable {
        var spanish: String
        var english: String
        var phrase: Bool
        var note: String
    }

    enum Failure: Error {
        /// This phone has used today's allowance.
        case allowance
        case refused
        case busy
        case other

        var message: String {
            switch self {
            case .allowance: "Claude ya no revisa más por hoy. Mañana sigue."
            case .refused: "Claude no pudo ayudar con este texto."
            case .busy: "Claude está ocupado. Prueba otra vez en un momento."
            case .other: "No se pudo hablar con Claude. Revisa la conexión y prueba otra vez."
            }
        }
    }

    // MARK: consent

    /// Asked once, before any reading is first sent.
    static var consented: Bool {
        get { UserDefaults.standard.bool(forKey: "tutorConsent") }
        set { UserDefaults.standard.set(newValue, forKey: "tutorConsent") }
    }

    static let consentTitle = "¿Enviar a Claude?"
    static let consentMessage = "Para revisar, el texto de la lectura y lo que escribas se envían a Claude, la IA de Anthropic. No se envía nada más tuyo, y no se guarda para entrenar modelos."

    /// The phone this is, to the proxy: a random ID made once, so each phone's allowance is counted on its own.
    private static var device: String {
        let key = "tutorDevice"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    // MARK: calls

    nonisolated struct LineInput: Encodable {
        var spanish: String
        var english = ""
        var attempt: String
    }

    /// Checks every line's translation. `enToEs` is Al revés: `attempt` is Spanish written from `english`.
    static func check(title: String, lines: [LineInput], enToEs: Bool) async throws(Failure) -> Check {
        if demo { return await demoCheck(lines, enToEs: enToEs) }
        struct Body: Encodable { let device, direction, title: String; let lines: [LineInput] }
        // The proxy turns away anything longer, so trim to its limits rather than fail.
        let body = Body(device: device, direction: enToEs ? "en-es" : "es-en", title: String(title.prefix(120)),
                        lines: lines.prefix(80).map {
                            LineInput(spanish: String($0.spanish.prefix(600)), english: String($0.english.prefix(600)),
                                      attempt: String($0.attempt.prefix(600)))
                        })
        return try await post("check", body, timeout: 90)
    }

    nonisolated struct GlossInput: Encodable {
        var text: String
        var sentence: String
        var english: String
    }

    /// A card for each marked word or phrase, in order.
    static func gloss(_ items: [GlossInput]) async throws(Failure) -> [Gloss] {
        if demo {
            try? await Task.sleep(for: .milliseconds(700))
            return items.map { Gloss(spanish: $0.text.lowercased(), english: "(demo) \($0.text)", phrase: false, note: "") }
        }
        struct Body: Encodable { let device: String; let items: [GlossInput] }
        struct Reply: Decodable { let items: [Gloss] }
        let body = Body(device: device, items: items.prefix(40).map {
            GlossInput(text: String($0.text.prefix(120)), sentence: String($0.sentence.prefix(600)), english: String($0.english.prefix(600)))
        })
        let reply: Reply = try await post("gloss", body, timeout: 60)
        return reply.items
    }

    private static func post<B: Encodable, R: Decodable>(_ path: String, _ body: B, timeout: TimeInterval) async throws(Failure) -> R {
        guard let base else { throw .other }
        var request = URLRequest(url: base.appending(path: path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { throw .other }
        switch status {
        case 200: break
        case 429: throw .allowance
        case 422: throw .refused
        case 503: throw .busy
        default: throw .other
        }
        guard let reply = try? JSONDecoder().decode(R.self, from: data) else { throw .other }
        return reply
    }

    private static func demoCheck(_ lines: [LineInput], enToEs: Bool) async -> Check {
        try? await Task.sleep(for: .milliseconds(900))
        var out = Check(lines: [], missed: [], notes: ["(demo) A friendly, informal register: tú throughout."])
        for (i, l) in lines.enumerated() {
            let blank = l.attempt.trimmingCharacters(in: .whitespaces).isEmpty
            let close = !blank && i % 3 == 1
            out.lines.append(LineCheck(verdict: blank ? "blank" : close ? "close" : "good",
                                       comment: close ? "(demo) Nearly: one word is off." : "",
                                       better: enToEs ? l.spanish : "(demo) English for line \(i + 1)"))
            if close, let w = l.spanish.split(separator: " ").last {
                out.missed.append(Missed(line: i, text: w.trimmingCharacters(in: .punctuationCharacters)))
            }
        }
        return out
    }
}
