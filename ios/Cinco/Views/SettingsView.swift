import SwiftUI
import SwiftData
import CloudKit

struct SettingsView: View {
    @AppStorage(PrefKey.newPerDay) private var newPerDay = 15
    @AppStorage(PrefKey.autoSpeak) private var autoSpeak = true
    @AppStorage(PrefKey.direction) private var direction = Direction.stage.rawValue
    @AppStorage(PrefKey.vosotros) private var vosotros = false
    @AppStorage(PrefKey.voiceLang) private var voiceLang = "es-MX"
    @AppStorage(PrefKey.theme) private var theme = "auto"

    @State private var iCloud = "Comprobando…"

    var body: some View {
        Form {
            Section("Estudio") {
                Stepper("Nuevas al día: \(newPerDay)", value: $newPerDay, in: 0...100, step: 5)
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
                Text("Con Latinoamérica suenan las grabaciones hechas en el Mac. Si una palabra no tiene grabación, habla la mejor voz de iOS instalada: descarga una voz Mejorada o Premium en Ajustes › Accesibilidad › Contenido leído › Voces › Español.")
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
        }
        .font(Typo.text(16))
        .navigationTitle("Ajustes")
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
                Text("Cada tarjeta sube cinco etapas. Cada etapa es más difícil que la anterior y tarda más en volver. Si aciertas, la tarjeta sube (toca ¡La sé! o desliza a la derecha). Si fallas (toca Otra vez o desliza a la izquierda), baja una etapa y vuelve unas tarjetas después en la misma sesión.")
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
                Text("Un verbo sale en Vocabulario en tres pasos: la palabra, su significado y luego sus tablas. En Conjugación cada tiempo de cada verbo es una tarjeta: primero ves el verbo, luego su significado y después conjugas la tabla. Primero la estudias, luego la dices en voz alta y te calificas, y desde la etapa 4 escribes las formas. El pronombre es opcional.")
                Text("Columnas del CSV: spanish, english, example, notes, tags. Solo las dos primeras son obligatorias. Los verbos pueden llevar una columna por tiempo (presente, preterito, imperfecto…), cada una con las seis formas separadas por |. Reimportar un archivo actualiza las tarjetas sin perder su progreso.")
            }
            .font(Typo.text(16))
            .foregroundStyle(Palette.ink)
            .padding(16)
        }
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle("Cómo funciona")
    }
}
