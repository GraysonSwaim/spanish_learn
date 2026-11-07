import SwiftUI
import SwiftData
import CloudKit

struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrefKey.stageCap) private var stageCap = Scheduler.defaultCap
    @AppStorage(PrefKey.autoSpeak) private var autoSpeak = true
    @AppStorage(PrefKey.direction) private var direction = Direction.stage.rawValue
    @AppStorage(PrefKey.vosotros) private var vosotros = false
    @AppStorage(PrefKey.voiceLang) private var voiceLang = "es-MX"
    @AppStorage(PrefKey.theme) private var theme = "auto"
    @AppStorage(PrefKey.askMnemonics) private var askMnemonics = true
    @AppStorage(PrefKey.examples) private var examples = Tutor.consented
    @AppStorage(PrefKey.newPerScan) private var newPerScan = Scheduler.defaultNewPerScan
    @AppStorage(PrefKey.reminder) private var reminder = false
    @AppStorage(PrefKey.reminderMinutes) private var reminderMinutes = Reminder.defaultMinutes

    @State private var iCloud = "Comprobando…"
    @State private var confirmErase = false
    @State private var reminderRefused = false

    /// The reminder's time, as the picker wants it.
    private var reminderTime: Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(reminderMinutes) * 60)
        } set: {
            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
            reminderMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Recordatorio diario", isOn: $reminder)
                if reminder {
                    DatePicker("Hora", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text(reminderRefused ? "iOS no tiene permiso para avisarte. Actívalo en Ajustes › Notificaciones › Choca Cinco."
                     : "Te avisa de cuántas tarjetas tienes para repasar. Los días que no tengas ninguna, no suena.")
            }
            .onChange(of: reminder) { _, on in
                Task {
                    if on, !(await Reminder.ask()) {
                        reminder = false
                        reminderRefused = true
                    }
                    if on, reminder { reminderRefused = false }
                    await Reminder.refresh(ctx)
                }
            }
            .onChange(of: reminderMinutes) { Task { await Reminder.refresh(ctx) } }
            Section("Estudio") {
                Stepper(value: $stageCap, in: 1...20) {
                    VStack(alignment: .leading) {
                        Text("Tarjetas por etapa: \(stageCap)")
                        Text("Cuántas caben en cada etapa de la 1 a la 4. Una nueva entra cuando hay sitio en la 1.").font(Typo.text(13)).foregroundStyle(Palette.muted)
                    }
                }
                Stepper(value: $newPerScan, in: 5...40, step: 5) {
                    VStack(alignment: .leading) {
                        Text("Palabras nuevas por escaneo: \(newPerScan)")
                        Text("Cuántas entran en tu biblioteca cada vez, las básicas primero. Las demás pueden esperar: añádelas desde la página, o llegarán con otra.").font(Typo.text(13)).foregroundStyle(Palette.muted)
                    }
                }
                Toggle("Pronunciar en voz alta", isOn: $autoSpeak)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dirección")
                    Picker("Dirección", selection: $direction) {
                        ForEach(Direction.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Text((Direction(rawValue: direction) ?? .stage).blurb).font(Typo.text(13)).foregroundStyle(Palette.muted)
                }
                Toggle(isOn: $vosotros) {
                    VStack(alignment: .leading) {
                        Text("Practicar vosotros")
                        Text("Las formas de España en la pestaña Conjugación").font(Typo.text(13)).foregroundStyle(Palette.muted)
                    }
                }
                Toggle(isOn: $askMnemonics) {
                    VStack(alignment: .leading) {
                        Text("Pedir mnemotecnias")
                        Text("Al fallar una tarjeta, un truco para recordarla").font(Typo.text(13)).foregroundStyle(Palette.muted)
                    }
                }
                Toggle(isOn: $examples) {
                    VStack(alignment: .leading) {
                        Text("Frases de ejemplo")
                        Text("Claude escribe una frase con cada palabra que no la tenga, y la traduce. Para eso se le envían el español y el inglés de tus tarjetas.").font(Typo.text(13)).foregroundStyle(Palette.muted)
                    }
                }
                .onChange(of: examples) { _, on in if on { Task { await Examples.fill(ctx) } } }
            }
            Section {
                Picker("Acento", selection: $voiceLang) {
                    Text("Latinoamérica").tag("es-MX")
                    Text("España").tag("es-ES")
                }
                Button("Probar la voz") { Speaker.shared.speak("Hola. ¿Me oyes bien?", lang: voiceLang) }
            } header: {
                Text("Voz")
            } footer: {
                Text("Habla la mejor voz de iOS instalada. Para que suene mucho mejor, descarga una voz Mejorada o Premium en Ajustes › Accesibilidad › Contenido leído › Voces › Español.")
            }
            Section {
                NavigationLink("Revisar mi biblioteca") { ReviewLibraryView() }
            } footer: {
                Text("Busca significados equivocados, comparando tus palabras con Apple Traducir y Apple Intelligence.")
            }
            Section {
                NavigationLink("Cómo funciona") { HowView() }
            }
            Section("Aspecto") {
                Picker("Tema", selection: $theme) {
                    Text("Automático").tag("auto")
                    Text("Claro").tag("light")
                    Text("Oscuro").tag("dark")
                }
            }
            Section {
                LabeledContent("iCloud", value: iCloud)
            } footer: {
                Text("Las tarjetas y el progreso se guardan en iCloud y se sincronizan entre tus dispositivos. Los ajustes se quedan en cada dispositivo.")
            }
            Section {
                NavigationLink("Créditos") { AcknowledgementsView() }
            }
            Section {
                Button("Borrar todos los datos", role: .destructive) { confirmErase = true }
                    .tint(Palette.again)
            } footer: {
                Text("Empieza de cero: borra todas las tarjetas, el progreso, la racha y las lecturas, aquí y en tus otros dispositivos con iCloud. Los ajustes se quedan.")
            }
        }
        .font(Typo.text(16))
        .navigationTitle("Ajustes")
        .confirmationDialog("¿Borrar todos los datos?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Borrar todo", role: .destructive) {
                Deck.eraseAll(ctx)
                dismiss()
            }
        } message: {
            Text("Tarjetas, progreso, racha y lecturas, en todos tus dispositivos. No se puede deshacer.")
        }
        .task { iCloud = await Self.accountStatus() }
    }

    static func accountStatus() async -> String {
        guard FileManager.default.ubiquityIdentityToken != nil else { return "Sin sesión: solo en este dispositivo" }
        return switch try? await CKContainer.default().accountStatus() {
        case .available: "Sincronizando"
        case .restricted: "Restringido"
        case .noAccount: "Sin sesión: solo en este dispositivo"
        case .temporarilyUnavailable: "No disponible por ahora"
        default: "Desconocido"
        }
    }
}

struct HowView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tienes una sola biblioteca de palabras, y cada palabra está una sola vez, por muchas páginas en las que salga. Se llena sola con lo que lees.")
                Text("Toca + y escanea una página, o pega el enlace de un artículo. Claude saca todas sus palabras y las ordena en tres niveles: básicas, intermedias y avanzadas. Las nuevas entran en tu biblioteca, las básicas primero, hasta el límite que digas en Ajustes.")
                Text("Luego estudias. Cada palabra nueva te la pregunta una vez: si dices Ya la sé, no hace falta entrenarla y te la pregunta a la semana; si dices No la sé, empieza a subir por las etapas. Primero salen las de lo que vas a leer, y empiezas en cuanto están listas; puedes salir cuando quieras y leer.")
                Text("Después lees. Toca lo que no entiendas y queda guardado. En amarillo, ya estaba en tu biblioteca, y vuelve a repasarse. En verde, es nueva, y acaba de entrar. Las que ya has estudiado salen en amarillo pálido, aunque estén conjugadas; se apaga con el rotulador de arriba.")
                Text("Cada tarjeta sube cinco etapas, cada una más difícil que la anterior. Si aciertas, sube (toca ¡La sé! o desliza a la derecha). Si fallas (toca Otra vez o desliza a la izquierda), baja una etapa y vuelve unas tarjetas después.")
                Text("De la 1 a la 4 caben pocas tarjetas a la vez: 5 en cada etapa, o las que digas en Ajustes. Así estudias pocas y las aprendes bien. Una tarjeta solo sube si en la siguiente etapa hay sitio; si no, queda lista y sube en cuanto lo hay. Una nueva entra cuando hay sitio en la 1.")
                Text("La sesión no se acaba sola: repasas sin esperas, tanto como quieras, y las nuevas van entrando. Las dominadas no tienen límite. Para que pasen a la memoria larga, te las pregunta a las 24 horas, a las 48 y a las 96; luego a la semana, a las 2 semanas, a las 4, a las 8… Cada palabra va por su cuenta: un fallo solo mueve esa palabra, que vuelve a empezar por las 24 horas. Si tocas una mientras lees, te la pregunta otra vez, y si la aciertas no pierde nada.")
                ForEach(1...5, id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i)").font(Typo.display(18)).foregroundStyle(.white)
                            .frame(width: 30, height: 30).background(Palette.stage(i), in: .rect(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(StageInfo.all[i].name).font(Typo.text(16, .heavy))
                            Text(StageInfo.all[i].blurb).foregroundStyle(Palette.muted)
                        }
                    }
                }
                Text("En Vocabulario ves la palabra o la expresión (¿Dónde está el baño?, Me da igual), su significado y una frase de ejemplo: con la palabra resaltada cuando la ves en español, y con un hueco cuando eres tú quien la dice o la escribe. Si a una tarjeta le falta la frase, Claude la escribe (Ajustes › Frases de ejemplo).")
                Text("En Conjugación cada tiempo de cada verbo es una tarjeta: primero ves el verbo, luego su significado y después conjugas la tabla. Primero la estudias, luego la dices en voz alta y te calificas, y desde la etapa 4 escribes las formas. El pronombre es opcional.")
                Text("Con + también puedes añadir una sola palabra: escríbela con su significado, y Claude corrige cómo se escribe y añade una frase de ejemplo y su nivel. Si ya está en tu biblioteca, no se repite.")
                Text("Si un significado te parece mal, toca ¿Está bien? bajo la respuesta: lo compara con Apple Traducir y Apple Intelligence, y con un toque lo cambias. Para mirar todas tus palabras de una vez, está Ajustes › Revisar mi biblioteca.")
                Text("Si fallas una tarjeta, puedes escribir en ese momento una mnemotecnia: un truco para recordarla. Aparece con la respuesta la próxima vez. Se puede desactivar en Ajustes.")
                Text("En la pantalla de inicio ves tu biblioteca, nivel por nivel. A largo plazo son las palabras que han superado las 24, las 48 y las 96 horas; las de Ya la sé cuentan cuando las aciertas a la semana.")
                Text("Tus tarjetas y tu progreso se guardan en iCloud y se sincronizan entre todos tus dispositivos con la misma cuenta. Los ajustes, como las tarjetas por etapa, se quedan en cada dispositivo.")
            }
            .font(Typo.text(16))
            .foregroundStyle(Palette.ink)
            .padding(16)
        }
        .background(Backdrop())
        .navigationTitle("Cómo funciona")
    }
}
