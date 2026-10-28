import AppKit
import SwiftUI
import Combine

/// Fotogramas ASCII por estado, cada uno con su duración en segundos.
/// Para pasar a imágenes basta con otro `PetRenderer`.
enum AsciiFrames {
    typealias Frame = (text: String, duration: TimeInterval)

    static func frames(for phase: Phase) -> [Frame] {
        switch phase {
        // Mira al frente y parpadea un instante cada 6 s.
        case .idle:     [("(◕‿◕)", 5.82), ("(−‿−)", 0.18)]
        // Los ojos se van llenando, dan la vuelta completa y vuelven a empezar.
        case .thinking: [("(○_○)", 0.22), ("(◔_◔)", 0.22), ("(◑_◑)", 0.22), ("(◕_◕)", 0.22), ("(●_●)", 0.45)]
        case .writing:  [("(•̀ᴗ•́)✎   ", 0.4), ("(•̀ᴗ•́)✎_  ", 0.4), ("(•̀ᴗ•́)✎__ ", 0.4), ("(•̀ᴗ•́)✎___", 0.4)]
        case .done:     [("(ﾉ◕‿◕)ﾉ !", 0.4), ("\\(◕‿◕)/ !", 0.4)]
        case .needsYou: [("(⊙_⊙) ?", 0.4), ("(⊙_⊙)  ", 0.4)]
        }
    }

    /// Dormida tras un rato sin actividad.
    static let sleeping: [Frame] = [("(−_−)    ", 0.9), ("(−_−) z  ", 0.9), ("(−_−) zZ ", 0.9), ("(−_−) zZz", 1.3)]

    /// Primer fotograma: la cara "quieta" de cada estado (para listas e iconos).
    static func still(for phase: Phase) -> String {
        phase == .thinking ? "(◑_◑)" : frames(for: phase)[0].text
    }

    static func frame(for phase: Phase, at date: Date) -> String {
        frame(in: frames(for: phase), at: date)
    }

    static func frame(in frames: [Frame], at date: Date) -> String {
        let total = frames.reduce(0) { $0 + $1.duration }
        var t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: total)
        for f in frames {
            if t < f.duration { return f.text }
            t -= f.duration
        }
        return frames[0].text
    }
}

/// Conversión entre el color elegido en ajustes y el hex guardado en `Pref.petColor`.
enum PetColor {
    static func color(from hex: String) -> Color? {
        guard hex.count == 7, hex.hasPrefix("#"), let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return Color(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static func hex(from color: Color) -> String {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return "" }
        let v = { (x: CGFloat) in Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", v(c.redComponent), v(c.greenComponent), v(c.blueComponent))
    }
}

extension View {
    /// Fondo de la mascota: Liquid Glass en macOS 26+, material translúcido en versiones anteriores.
    func petGlass() -> some View {
        background(GeometryReader { g in PetGlassBackground(cornerRadius: g.size.height / 2) })
            .clipShape(Capsule())
    }
}

/// Cristal de AppKit en vez del de SwiftUI: el panel de la mascota nunca es la ventana activa
/// y así el fondo no se vuelve opaco por estar "inactivo".
private struct PetGlassBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear
            return glass
        }
        let fx = NSVisualEffectView()
        fx.material = .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        return fx
    }

    func updateNSView(_ view: NSView, context: Context) {
        if #available(macOS 26, *), let glass = view as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        }
    }
}

extension UserDefaults {
    /// Para observar `Pref.petStyle` con KVO (el nombre tiene que coincidir con la clave).
    @objc dynamic var petStyle: String? { string(forKey: Pref.petStyle) }
}

/// Aspecto de la mascota elegido en ajustes (`Pref.petStyle`).
enum PetStyle: String {
    case ascii, sprites

    static var current: PetStyle {
        PetStyle(rawValue: UserDefaults.standard.string(forKey: Pref.petStyle) ?? "") ?? .sprites
    }
}

/// Mascota animada a partir de Resources/PetSprites.png: celdas de 192 × 208 px, una animación
/// por fila en el orden de los estados (reposo, pensando, trabajando, guiño, cara feliz,
/// te necesita, dormido). Los dibujos son blancos sobre transparente y se tiñen con el color
/// de la mascota.
enum SpriteFrames {
    private static let cell = CGSize(width: 192, height: 208)

    /// Fotograma: fila y columna de la hoja y cuánto dura en pantalla.
    private typealias Frame = (row: Int, col: Int, duration: TimeInterval)
    /// Fotogramas y zona de la celda que ocupan todos ellos (así el dibujo queda centrado).
    private typealias Animation = (frames: [Frame], crop: CGRect)

    private static func row(_ r: Int, _ cols: Range<Int>, _ duration: TimeInterval) -> [Frame] {
        cols.map { (r, $0, duration) }
    }

    private static func animation(for phase: Phase) -> Animation {
        switch phase {
        // Mira al frente y parpadea un instante cada 6 s, como la versión ASCII.
        case .idle:     (row(0, 0..<1, 5.82) + row(0, 1..<2, 0.18), CGRect(x: 31, y: 54, width: 130, height: 70))
        case .thinking: (row(1, 0..<6, 0.18), CGRect(x: 31, y: 52, width: 131, height: 74))   // los ojos se van cargando
        case .writing:  (row(2, 0..<6, 0.12), CGRect(x: 29, y: 52, width: 135, height: 144))  // escribiendo en el teclado
        // Terminado: guiña un ojo y se queda con cara feliz un rato antes de repetir.
        case .done:     (row(3, 0..<4, 0.16) + row(4, 0..<5, 0.18) + row(4, 4..<5, 1.6),
                         CGRect(x: 30, y: 57, width: 132, height: 68))
        case .needsYou: (row(5, 0..<8, 0.14), CGRect(x: 30, y: 25, width: 146, height: 96))  // con el interrogante
        }
    }

    /// Ojos cerrados con las "z".
    private static let sleeping: Animation = (row(6, 0..<4, 0.6), CGRect(x: 31, y: 45, width: 131, height: 79))

    /// Puntos por píxel de la hoja y caja fija donde se centra cada animación.
    static let scale: CGFloat = 0.44
    static let box = CGSize(width: 164 * scale, height: 170 * scale)

    private static let image: CGImage? = {
        guard let url = Bundle.main.url(forResource: "PetSprites", withExtension: "png"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }()

    static var isAvailable: Bool { image != nil }

    private static var cache: [String: CGImage] = [:]

    /// Fotograma de ahora ya recortado; nil si la hoja no está en la app.
    static func frame(for phase: Phase, asleep: Bool, at date: Date) -> CGImage? {
        guard let image else { return nil }
        let a = asleep ? sleeping : animation(for: phase)
        let total = a.frames.reduce(0) { $0 + $1.duration }
        var t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: total)
        var f = a.frames[0]
        for candidate in a.frames {
            if t < candidate.duration { f = candidate; break }
            t -= candidate.duration
        }
        let key = "\(f.row),\(f.col),\(a.crop)"
        if let hit = cache[key] { return hit }
        let rect = a.crop.offsetBy(dx: CGFloat(f.col) * cell.width, dy: CGFloat(f.row) * cell.height)
        guard let cut = image.cropping(to: rect) else { return nil }
        cache[key] = cut
        return cut
    }
}

struct PetRenderer: View {
    let phase: Phase
    /// Última actividad de Claude; en reposo, pasado `SessionMonitor.sleepAfter` se duerme.
    var lastActivity: Date = .distantFuture
    @AppStorage(Pref.petColor) private var petColor = ""
    @AppStorage(Pref.petStyle) private var petStyle = PetStyle.sprites.rawValue

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { ctx in
            let asleep = phase == .idle && ctx.date.timeIntervalSince(lastActivity) > SessionMonitor.sleepAfter
            let tint = PetColor.color(from: petColor).map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary)
            Group {
                if petStyle == PetStyle.sprites.rawValue,
                   let frame = SpriteFrames.frame(for: phase, asleep: asleep, at: ctx.date) {
                    Image(decorative: frame, scale: 1)
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: CGFloat(frame.width) * SpriteFrames.scale,
                               height: CGFloat(frame.height) * SpriteFrames.scale)
                        .frame(width: SpriteFrames.box.width, height: SpriteFrames.box.height)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                } else {
                    Text(asleep ? AsciiFrames.frame(in: AsciiFrames.sleeping, at: ctx.date)
                                : AsciiFrames.frame(for: phase, at: ctx.date))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                }
            }
            .foregroundStyle(tint)
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
            .petGlass()
            .overlay(Capsule().stroke(phase >= .done ? Color.orange : .clear, lineWidth: 2))
            .fixedSize()
        }
    }
}

struct BubbleView: View {
    let session: ClaudeSession
    let onOpen: () -> Void
    let onReply: (ReplyOption) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 16, height: 16)
                Text(session.name).font(.caption.bold()).lineLimit(1)
                Spacer()
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.secondary)
                    .help(L("Cerrar y dejar de avisar", "Close and stop alerting"))
            }
            // Máximo 4 líneas entre el mensaje y la pregunta.
            if let summary = session.summary {
                Text(summary).font(.callout).lineLimit(session.question == nil ? 4 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let question = session.question {
                Text(question).font(.callout.bold()).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !session.options.isEmpty {
                FlowOptions(options: session.options, onReply: onReply)
            }
            Text(session.options.isEmpty ? L("Clic para abrir el chat", "Click to open the chat")
                                         : L("Clic en una opción: se copia y abre el chat", "Click an option: it is copied and the chat opens"))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 260, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.6)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

private struct FlowOptions: View {
    let options: [ReplyOption]
    let onReply: (ReplyOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(options, id: \.self) { opt in
                Button { onReply(opt) } label: {
                    Text(opt.label).font(.caption).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(opt.message)
            }
        }
    }
}

/// Dónde están los globos respecto a la mascota; decide el orden de la pila.
final class BubbleLayout: ObservableObject {
    @Published var belowPet = false
}

struct BubblesView: View {
    @ObservedObject var monitor: SessionMonitor
    @ObservedObject var layout: BubbleLayout
    static let maxShown = 3

    var body: some View {
        let all = monitor.alerts
        let shown = Array(all.prefix(Self.maxShown))
        // La más reciente siempre queda junto a la mascota.
        let ordered = layout.belowPet ? shown : shown.reversed()
        VStack(spacing: 6) {
            if !layout.belowPet { more(all.count - shown.count) }
            ForEach(ordered) { s in
                BubbleView(
                    session: s,
                    onOpen: { open(s) },
                    onReply: { opt in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(opt.message, forType: .string)
                        open(s)
                    },
                    onDismiss: { monitor.acknowledge(s.id) }
                )
            }
            if layout.belowPet { more(all.count - shown.count) }
        }
        .padding(6)
        .fixedSize()
    }

    @ViewBuilder private func more(_ n: Int) -> some View {
        if n > 0 {
            Text(L("+\(n) más en la barra de menús", "+\(n) more in the menu bar"))
                .font(.caption2).padding(.horizontal, 8).padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
        }
    }

    private func open(_ s: ClaudeSession) {
        monitor.acknowledge(s.id)
        openInClaude(s)
    }
}

/// Espacio libre desde el centro de la mascota hasta los bordes de su pantalla.
final class PetEdges: ObservableObject {
    @Published var left: CGFloat = 150
    @Published var right: CGFloat = 150
}

struct PetView: View {
    @ObservedObject var monitor: SessionMonitor
    @ObservedObject var edges: PetEdges
    let onDrag: (_ ended: Bool) -> Void

    var body: some View {
        let focus = monitor.focus
        let alerts = monitor.alerts.count
        VStack(spacing: 4) {
            PetRenderer(phase: focus?.phase ?? .idle, lastActivity: monitor.lastActivity)
                .overlay(alignment: .topTrailing) {
                    if alerts > 1 {
                        Text("\(alerts)").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(4).background(Color.orange, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
                .onTapGesture {
                    if let s = focus, s.phase != .idle {
                        monitor.acknowledge(s.id)
                        openInClaude(s)
                    } else if monitor.isSleeping {
                        monitor.wake()
                    } else if let s = focus {
                        openInClaude(s)
                    }
                }
                .gesture(DragGesture(minimumDistance: 3)
                    .onChanged { _ in onDrag(false) }
                    .onEnded { _ in onDrag(true) })
            statusLine
        }
        .padding(.top, 8)
        .frame(width: PetWindowController.petSize.width, height: PetWindowController.petSize.height, alignment: .top)
        .animation(.spring(duration: 0.3), value: focus?.phase)
    }

    /// "Pensando… · Castell" o "3 trabajando · Castell, AWP…"
    @ViewBuilder private var statusLine: some View {
        let busy = monitor.sessions.filter { $0.phase == .thinking || $0.phase == .writing }
        if busy.count == 1, let s = busy.first {
            caption("\(s.phase.label)\n\(s.name)")
        } else if busy.count > 1 {
            caption(L("\(busy.count) trabajando", "\(busy.count) working") + "\n\(busy.map(\.name).joined(separator: ", "))")
        }
    }

    private func caption(_ text: String) -> some View {
        EdgeAwareCaption(text: text, edges: edges)
    }
}

/// Texto bajo la mascota: centrado, pero se desplaza hacia dentro si se saldría de la pantalla
/// y se recorta con "…" si no cabe.
private struct EdgeAwareCaption: View {
    let text: String
    @ObservedObject var edges: PetEdges
    @State private var width: CGFloat = 0
    private let margin: CGFloat = 6

    var body: some View {
        let maxWidth = max(40, min(PetWindowController.petSize.width - 2 * margin, edges.left + edges.right - 2 * margin))
        let w = min(width, maxWidth)
        // Desplazamiento del centro del texto para que quede entre los dos bordes.
        let lo = -edges.left + margin + w / 2
        let hi = edges.right - margin - w / 2
        let dx = lo > hi ? 0 : min(max(0, lo), hi)
        Text(text).font(.caption2).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
            // Sombra negra suave para que se lea también sobre fondos blancos.
            .shadow(color: .black.opacity(0.55), radius: 1.5, x: 0, y: 0.5)
            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 0)
            // Se mide el texto ya recortado (nunca más ancho que maxWidth)…
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { width = geo.size.width }
                    .onChange(of: geo.size.width) { _, new in width = new }
            })
            // …y luego se centra bajo la mascota y se desplaza lo justo.
            .frame(maxWidth: maxWidth)
            .offset(x: dx)
            .animation(.easeOut(duration: 0.15), value: dx)
    }
}

/// Panel transparente que macOS no recoloca: así la mascota puede ir a cualquier
/// parte del escritorio, también pegada al borde superior de una segunda pantalla.
private final class FreePanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// La mascota y sus globos van en dos paneles: la mascota se mueve libre y los globos
/// se colocan encima, debajo, a la derecha o a la izquierda según quepan en la pantalla.
@MainActor
final class PetWindowController {
    static let petSize = NSSize(width: 300, height: 126)
    private let gap: CGFloat = 2

    private let panel = FreePanel(size: petSize)
    private let bubblePanel = FreePanel(size: .zero)
    private let bubbleHost: NSHostingView<BubblesView>
    private let layout = BubbleLayout()
    private let edges = PetEdges()
    private let monitor: SessionMonitor
    private var dragOffset: NSPoint?
    private var bag: Set<AnyCancellable> = []

    init(monitor: SessionMonitor) {
        self.monitor = monitor
        bubbleHost = NSHostingView(rootView: BubblesView(monitor: monitor, layout: layout))
        bubblePanel.contentView = bubbleHost

        let host = NSHostingView(rootView: PetView(monitor: monitor, edges: edges) { [weak self] ended in
            self?.drag(ended: ended)
        })
        host.frame = NSRect(origin: .zero, size: Self.petSize)
        panel.contentView = host

        if panel.setFrameUsingName("ClaudioPet2") {
            // Mantiene el borde superior aunque el panel haya cambiado de alto entre versiones.
            let saved = panel.frame
            panel.setFrame(NSRect(x: saved.minX, y: saved.maxY - Self.petSize.height,
                                  width: Self.petSize.width, height: Self.petSize.height), display: false)
        } else if let old = UserDefaults.standard.string(forKey: "NSWindow Frame ClaudioPet") {
            // Posición de la versión anterior (panel de 560 pt con la mascota abajo).
            let parts = old.split(separator: " ").compactMap { Double($0) }
            if parts.count >= 2 { panel.setFrameOrigin(NSPoint(x: parts[0], y: parts[1])) } else { resetPosition() }
        } else {
            resetPosition()
        }
        panel.setFrameAutosaveName("ClaudioPet2")
        keepOnScreen()
        updateEdges()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.keepOnScreen()
                self?.updateEdges()
                self?.placeBubbles()
            }
        }
        UserDefaults.standard.publisher(for: \.petStyle).removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateEdges(); self?.placeBubbles() }
        }.store(in: &bag)
        monitor.$sessions.sink { [weak self] _ in
            DispatchQueue.main.async { self?.placeBubbles() }
        }.store(in: &bag)
    }

    // MARK: Posición de la mascota

    /// Esquina inferior derecha de la pantalla principal.
    func resetPosition() {
        guard let screen = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: screen.maxX - Self.petSize.width - 20, y: screen.minY + 12))
        panel.saveFrame(usingName: "ClaudioPet2")
        placeBubbles()
    }

    /// Zona visible de la mascota dentro de su panel (centrada arriba).
    private var petRect: NSRect {
        let f = panel.frame
        if PetStyle.current == .sprites && SpriteFrames.isAvailable {
            let h = SpriteFrames.box.height + 8, w = SpriteFrames.box.width + 20
            return NSRect(x: f.midX - w / 2, y: f.maxY - 8 - h, width: w, height: h)
        }
        return NSRect(x: f.midX - 70, y: f.maxY - 52, width: 140, height: 46)
    }

    /// Si la mascota ha quedado fuera de todas las pantallas (p. ej. al desconectar un monitor),
    /// la mete en la pantalla más cercana o la devuelve a la esquina.
    private func keepOnScreen() {
        let pet = petRect
        let screens = NSScreen.screens.map(\.frame)
        if screens.contains(where: { $0.contains(pet) }) { return }
        guard let best = screens.max(by: { $0.intersection(pet).area < $1.intersection(pet).area }),
              best.intersection(pet).area > 0 else { resetPosition(); return }
        var dx: CGFloat = 0, dy: CGFloat = 0
        if pet.minX < best.minX { dx = best.minX - pet.minX } else if pet.maxX > best.maxX { dx = best.maxX - pet.maxX }
        if pet.minY < best.minY { dy = best.minY - pet.minY } else if pet.maxY > best.maxY { dy = best.maxY - pet.maxY }
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX + dx, y: panel.frame.minY + dy))
        panel.saveFrame(usingName: "ClaudioPet2")
    }

    private func drag(ended: Bool) {
        let mouse = NSEvent.mouseLocation
        if ended {
            dragOffset = nil
            keepOnScreen()
            updateEdges()
            panel.saveFrame(usingName: "ClaudioPet2")
            placeBubbles()
            return
        }
        let offset = dragOffset ?? NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        dragOffset = offset
        panel.setFrameOrigin(NSPoint(x: mouse.x - offset.x, y: mouse.y - offset.y))
        updateEdges()
        placeBubbles()
    }

    /// Cuánto sitio hay a cada lado de la mascota hasta el borde de su pantalla (máximo, medio panel).
    private func updateEdges() {
        let pet = petRect
        let center = NSPoint(x: pet.midX, y: pet.midY)
        guard let screen = (NSScreen.screens.first { $0.frame.contains(center) } ?? panel.screen)?.frame else { return }
        let half = Self.petSize.width / 2
        let left = min(max(center.x - screen.minX, 0), half)
        let right = min(max(screen.maxX - center.x, 0), half)
        if edges.left != left { edges.left = left }
        if edges.right != right { edges.right = right }
    }

    // MARK: Globos

    /// Encima de la mascota si caben; si no, debajo, a la derecha o a la izquierda.
    private func placeBubbles() {
        guard panel.isVisible, !monitor.alerts.isEmpty else {
            fadeOutBubbles()
            return
        }
        let pet = petRect
        let screen = (NSScreen.screens.first { $0.frame.contains(NSPoint(x: pet.midX, y: pet.midY)) }
                      ?? panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero

        func clampX(_ x: CGFloat, _ w: CGFloat) -> CGFloat { min(max(x, screen.minX), screen.maxX - w) }
        func clampY(_ y: CGFloat, _ h: CGFloat) -> CGFloat { min(max(y, screen.minY), screen.maxY - h) }

        let size = measuredBubbleSize()
        let candidates: [(below: Bool, origin: (NSSize) -> NSPoint)] = [
            (false, { s in NSPoint(x: clampX(pet.midX - s.width / 2, s.width), y: pet.maxY + self.gap) }),
            (true,  { s in NSPoint(x: clampX(pet.midX - s.width / 2, s.width), y: pet.minY - self.gap - s.height) }),
            (false, { s in NSPoint(x: pet.maxX + self.gap, y: clampY(pet.minY, s.height)) }),
            (false, { s in NSPoint(x: pet.minX - self.gap - s.width, y: clampY(pet.minY, s.height)) }),
        ]
        var chosen = candidates[0]
        for c in candidates {
            let o = c.origin(size)
            if screen.contains(NSRect(origin: o, size: size)) { chosen = c; break }
        }
        if layout.belowPet != chosen.below { layout.belowPet = chosen.below }
        var origin = chosen.origin(size)
        // Si no cabe en ningún lado, al menos que no se salga de la pantalla.
        origin = NSPoint(x: clampX(origin.x, size.width), y: clampY(origin.y, size.height))
        bubblePanel.setFrame(NSRect(origin: origin, size: size), display: true)
        fadeInBubbles()
    }

    private var measured: (key: String, size: NSSize)?

    /// Tamaño de los globitos con el contenido de *ahora*. El panel visible aún no ha redibujado
    /// el contenido nuevo cuando llega el aviso, así que se mide con una vista nueva, que se
    /// calcula al momento. Se guarda mientras el contenido no cambie. El orden de la pila
    /// (encima o debajo) no cambia el tamaño.
    private func measuredBubbleSize() -> NSSize {
        let alerts = monitor.alerts
        let key = alerts.prefix(BubblesView.maxShown).map {
            "\($0.id)|\($0.updatedAt.timeIntervalSince1970)|\($0.name)|\($0.summary ?? "")|\($0.question ?? "")|\($0.options.map(\.label))"
        }.joined(separator: "#") + "#\(alerts.count)"
        if let m = measured, m.key == key { return m.size }
        let probe = NSHostingView(rootView: BubblesView(monitor: monitor, layout: BubbleLayout()))
        let size = probe.fittingSize
        measured = (key, size)
        return size
    }

    private var fadingOut = false

    private func fadeInBubbles() {
        guard !bubblePanel.isVisible || fadingOut else { return }
        fadingOut = false
        if !bubblePanel.isVisible { bubblePanel.alphaValue = 0 }
        bubblePanel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            bubblePanel.animator().alphaValue = 1
        }
    }

    private func fadeOutBubbles() {
        guard bubblePanel.isVisible, !fadingOut else { return }
        fadingOut = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.6
            bubblePanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.fadingOut else { return }   // volvió a aparecer mientras tanto
                self.fadingOut = false
                self.bubblePanel.orderOut(nil)
                self.bubblePanel.alphaValue = 1
            }
        })
    }

    // MARK: Visibilidad

    var isVisible: Bool { panel.isVisible }

    func show() {
        keepOnScreen()
        panel.orderFrontRegardless()
        placeBubbles()
        UserDefaults.standard.set(true, forKey: "petVisible")
    }

    func hide() {
        panel.orderOut(nil)
        bubblePanel.orderOut(nil)
        UserDefaults.standard.set(false, forKey: "petVisible")
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
