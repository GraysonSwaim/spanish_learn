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

    @State private var iCloud = "Comprobando…"
    @State private var confirmErase = false

    var body: some View {
        Form {
            Section("Estudio") {
                Stepper(value: $stageCap, in: 1...20) {
                    VStack(alignment: .leading) {
                        Text("Tarjetas por etapa: \(stageCap)")
                        Text("Cuántas caben en cada etapa de la 1 a la 4. Una nueva entra cuando hay sitio en la 1.").font(Typo.text(13)).foregroundStyle(Palette.muted)
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
                Text("Cada tarjeta sube cinco etapas, cada una más difícil que la anterior. Si aciertas, sube (toca ¡La sé! o desliza a la derecha). Si fallas (toca Otra vez o desliza a la izquierda), baja una etapa y vuelve unas tarjetas después.")
                Text("De la 1 a la 4 caben pocas tarjetas a la vez: 5 en cada etapa, o las que digas en Ajustes. Así estudias pocas y las aprendes bien. Una tarjeta solo sube si en la siguiente etapa hay sitio; si no, queda lista y sube en cuanto lo hay. Una nueva entra cuando hay sitio en la 1. Un fallo baja la tarjeta aunque la etapa de abajo esté llena, y no entra ninguna nueva hasta que un acierto vuelve a hacer sitio.")
                Text("La sesión no se acaba sola: repasas las etapas 1 a 4 sin esperas, tanto como quieras, y las nuevas van entrando. Las dominadas no tienen límite: vuelven a la semana y, si las aciertas, a las 2 semanas, a las 4, a las 8… Toca la columna Dominada para repasarlas cuando quieras.")
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
                Text("Las tarjetas llegan de dos sitios: Añadir, una palabra cada vez, y Lecturas, donde marcas las que no conoces. Si una ya está en el mazo, no se repite.")
                Text("Si fallas una tarjeta, puedes escribir en ese momento una mnemotecnia: un truco para recordarla. Aparece con la respuesta la próxima vez. Se puede desactivar en Ajustes.")
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
