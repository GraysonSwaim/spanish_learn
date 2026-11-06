import SwiftUI
import SwiftData
import VisionKit

/// Scan a page of the book you're reading: its text becomes a reading, and its words feed the library (`ReadingView`).
/// The book's name is asked once and remembered.
struct ScanCard: View {
    @Environment(\.modelContext) private var ctx
    /// The scanned page, opened to take its words.
    let onCreate: (Reading) -> Void

    @AppStorage("scanBook") private var book = ""
    @State private var naming = false
    @State private var draftName = ""
    @State private var scanning = false
    @State private var reading = false
    @State private var failed = false

    private static var demo: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-scanSample")
        #else
        false
        #endif
    }

    /// Simulators and a few old devices have no document camera.
    static var available: Bool { VNDocumentCameraViewController.isSupported || demo }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background { Gloss(color: Palette.accent, shape: RoundedRectangle(cornerRadius: 6), lift: 0.6) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Escanear un libro").font(Typo.display(22)).foregroundStyle(Palette.ink)
                    Text("Sus palabras entran en tu biblioteca: las estudias y luego la lees.")
                        .font(Typo.text(15)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: scan) {
                HStack(spacing: 10) {
                    if reading { ProgressView().tint(.white) }
                    Text(reading ? "Leyendo la página…" : "Escanear una página").frame(maxWidth: reading ? nil : .infinity)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftButtonStyle(fill: Palette.accent, text: .white, size: 18))
            .disabled(reading)

            if !book.isEmpty {
                Button { askName() } label: {
                    HStack(spacing: 6) {
                        Text("Libro: \(book)").lineLimit(1)
                        Text("Cambiar").foregroundStyle(Palette.accentInk)
                    }
                    .font(Typo.text(15, .bold)).foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
            }

            if failed {
                Text("No se pudo leer el texto. Prueba con más luz y con el iPhone recto sobre la página.")
                    .font(Typo.text(14, .bold)).foregroundStyle(Palette.again)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .panel()
        .alert("¿Qué libro estás leyendo?", isPresented: $naming) {
            TextField("Título", text: $draftName)
            Button("Seguir") {
                let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                book = name.isEmpty ? "Mi libro" : name
                startScanning()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Sus páginas se guardan en Lecturas con ese nombre.")
        }
        .fullScreenCover(isPresented: $scanning) {
            PageCamera { images in
                scanning = false
                if !images.isEmpty { read(images) }
            }
            .ignoresSafeArea()
        }
    }

    private func scan() {
        if book.isEmpty { askName() } else { startScanning() }
    }

    private func askName() {
        draftName = book
        naming = true
    }

    private func startScanning() {
        failed = false
        #if DEBUG
        if Self.demo {
            create(pages: [ScannedPage(paragraphs: ScanCard.sample, number: 47)])
            return
        }
        #endif
        scanning = true
    }

    private func read(_ images: [UIImage]) {
        reading = true
        Task {
            let pages = await PageScan.read(images)
            reading = false
            create(pages: pages)
        }
    }

    private func create(pages: [ScannedPage]) {
        let lines = PageText.joined(pages)
        guard !lines.isEmpty else { failed = true; return }
        let r = Reading(title: PageScan.title(book: book, pages: pages), lines: lines)
        r.book = book
        ctx.insert(r)
        try? ctx.save()
        onCreate(r)
    }

    #if DEBUG
    /// `-scanSample`: a page for trying this in the simulator, which has no camera.
    static let sample = [
        "Aquella mañana, cuando el coronel abrió la ventana, le pareció que el pueblo entero se había quedado dormido bajo el peso de la lluvia. ¿Quién iba a pensar que tanta desdicha cabría en una sola semana? Echó de menos a su hermano, y a duras penas contuvo las lágrimas.",
        "Bajó las escaleras sin hacer ruido. En la cocina olía a café recién hecho y a leña mojada.",
        "—¿Adónde vas tan temprano? —le preguntó su mujer, sin levantar la vista del remiendo.",
        "—A ninguna parte —contestó él, y se encogió de hombros.",
    ]
    #endif
}

/// Apple's document camera: it finds the page's edges, flattens it, and takes as many as you like.
private struct PageCamera: UIViewControllerRepresentable {
    /// The pages taken, none when cancelled.
    let onDone: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController()
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ camera: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onDone: ([UIImage]) -> Void

        init(onDone: @escaping ([UIImage]) -> Void) { self.onDone = onDone }

        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onDone((0..<min(scan.pageCount, PageScan.maxPages)).map(scan.imageOfPage))
        }

        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { onDone([]) }

        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) { onDone([]) }
    }
}
