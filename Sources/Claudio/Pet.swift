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
        case .done:     [("(ﾉ◕ヮ◕)ﾉ !", 0.4), ("\\(◕ヮ◕)/ !", 0.4)]
        case .needsYou: [("(⊙_⊙) ?", 0.4), ("(⊙_⊙)  ", 0.4)]
        }
    }

    /// Primer fotograma: la cara "quieta" de cada estado (para listas e iconos).
    static func still(for phase: Phase) -> String {
        phase == .thinking ? "(◑_◑)" : frames(for: phase)[0].text
    }

    static func frame(for phase: Phase, at date: Date) -> String {
        let frames = frames(for: phase)
        let total = frames.reduce(0) { $0 + $1.duration }
        var t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: total)
        for f in frames {
            if t < f.duration { return f.text }
            t -= f.duration
        }
        return frames[0].text
    }
}

struct PetRenderer: View {
    let phase: Phase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { ctx in
            Text(AsciiFrames.frame(for: phase, at: ctx.date))
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
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
                    .help("Cerrar y dejar de avisar")
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
            Text(session.options.isEmpty ? "Clic para abrir el chat" : "Clic en una opción: se copia y abre el chat")
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
            Text("+\(n) más en la barra de menús")
                .font(.caption2).padding(.horizontal, 8).padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
        }
    }

    private func open(_ s: ClaudeSession) {
        monitor.acknowledge(s.id)
        openInClaude(s)
    }
}

struct PetView: View {
    @ObservedObject var monitor: SessionMonitor
    let onDrag: (_ ended: Bool) -> Void

    var body: some View {
        let focus = monitor.focus
        let alerts = monitor.alerts.count
        VStack(spacing: 4) {
            PetRenderer(phase: focus?.phase ?? .idle)
                .overlay(alignment: .topTrailing) {
                    if alerts > 1 {
                        Text("\(alerts)").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(4).background(Color.orange, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
                .onTapGesture {
                    if let s = focus {
                        monitor.acknowledge(s.id)
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
            Text("\(s.phase.label) · \(s.name)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        } else if busy.count > 1 {
            Text("\(busy.count) trabajando · \(busy.map(\.name).joined(separator: ", "))")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
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
    static let petSize = NSSize(width: 300, height: 76)
    private let gap: CGFloat = 2

    private let panel = FreePanel(size: petSize)
    private let bubblePanel = FreePanel(size: .zero)
    private let bubbleHost: NSHostingView<BubblesView>
    private let layout = BubbleLayout()
    private let monitor: SessionMonitor
    private var dragOffset: NSPoint?
    private var bag: Set<AnyCancellable> = []

    init(monitor: SessionMonitor) {
        self.monitor = monitor
        bubbleHost = NSHostingView(rootView: BubblesView(monitor: monitor, layout: layout))
        bubblePanel.contentView = bubbleHost

        let host = NSHostingView(rootView: PetView(monitor: monitor) { [weak self] ended in
            self?.drag(ended: ended)
        })
        host.frame = NSRect(origin: .zero, size: Self.petSize)
        panel.contentView = host

        if panel.setFrameUsingName("ClaudioPet2") {
            panel.setFrame(NSRect(origin: panel.frame.origin, size: Self.petSize), display: false)
        } else if let old = UserDefaults.standard.string(forKey: "NSWindow Frame ClaudioPet") {
            // Posición de la versión anterior (panel de 560 pt con la mascota abajo).
            let parts = old.split(separator: " ").compactMap { Double($0) }
            if parts.count >= 2 { panel.setFrameOrigin(NSPoint(x: parts[0], y: parts[1])) } else { resetPosition() }
        } else {
            resetPosition()
        }
        panel.setFrameAutosaveName("ClaudioPet2")
        keepOnScreen()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.keepOnScreen()
                self?.placeBubbles()
            }
        }
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
            panel.saveFrame(usingName: "ClaudioPet2")
            placeBubbles()
            return
        }
        let offset = dragOffset ?? NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        dragOffset = offset
        panel.setFrameOrigin(NSPoint(x: mouse.x - offset.x, y: mouse.y - offset.y))
        placeBubbles()
    }

    // MARK: Globos

    /// Encima de la mascota si caben; si no, debajo, a la derecha o a la izquierda.
    private func placeBubbles() {
        guard panel.isVisible, !monitor.alerts.isEmpty else {
            bubblePanel.orderOut(nil)
            return
        }
        let pet = petRect
        let screen = (NSScreen.screens.first { $0.frame.contains(NSPoint(x: pet.midX, y: pet.midY)) }
                      ?? panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero

        func clampX(_ x: CGFloat, _ w: CGFloat) -> CGFloat { min(max(x, screen.minX), screen.maxX - w) }
        func clampY(_ y: CGFloat, _ h: CGFloat) -> CGFloat { min(max(y, screen.minY), screen.maxY - h) }

        // El tamaño depende del orden (el "+N" va arriba o abajo), pero no de cuánto mide.
        var size = bubbleHost.fittingSize
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
        if layout.belowPet != chosen.below {
            layout.belowPet = chosen.below
            bubbleHost.layoutSubtreeIfNeeded()
            size = bubbleHost.fittingSize
        }
        var origin = chosen.origin(size)
        // Si no cabe en ningún lado, al menos que no se salga de la pantalla.
        origin = NSPoint(x: clampX(origin.x, size.width), y: clampY(origin.y, size.height))
        bubblePanel.setFrame(NSRect(origin: origin, size: size), display: true)
        bubblePanel.orderFrontRegardless()
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
