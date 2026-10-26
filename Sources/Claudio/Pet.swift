import AppKit
import SwiftUI

/// Fotogramas ASCII por estado. Para pasar a imágenes basta con otro `PetRenderer`.
enum AsciiFrames {
    static func frames(for phase: Phase) -> [String] {
        switch phase {
        case .idle:     ["(◕‿◕)", "(◕‿◕)", "(◕‿◕)", "(−‿−)"]
        case .thinking: ["(◔_◔)   ", "(◔_◔) .  ", "(◑_◑) .. ", "(◑_◑) ..."]
        case .writing:  ["(•̀ᴗ•́)✎   ", "(•̀ᴗ•́)✎_  ", "(•̀ᴗ•́)✎__ ", "(•̀ᴗ•́)✎___"]
        case .done:     ["(ﾉ◕ヮ◕)ﾉ !", "\\(◕ヮ◕)/ !"]
        case .needsYou: ["(⊙_⊙) ?", "(⊙_⊙)  "]
        }
    }
}

struct PetRenderer: View {
    let phase: Phase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { ctx in
            let frames = AsciiFrames.frames(for: phase)
            let i = Int(ctx.date.timeIntervalSinceReferenceDate / 0.4) % frames.count
            Text(frames[i])
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
            HStack {
                Text(session.name).font(.caption.bold()).lineLimit(1)
                Spacer()
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.secondary)
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

struct PetView: View {
    @ObservedObject var monitor: SessionMonitor
    let onDrag: (_ ended: Bool) -> Void
    /// Globitos cerrados con la ✕: id de sesión → momento del estado que se cerró.
    @State private var dismissed: [String: Date] = [:]

    private var bubbles: [ClaudeSession] {
        monitor.alerts.filter { dismissed[$0.id] != $0.updatedAt }
    }

    var body: some View {
        let focus = monitor.focus
        let shown = Array(bubbles.prefix(3))
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            if bubbles.count > shown.count {
                Text("+\(bubbles.count - shown.count) más en la barra de menús")
                    .font(.caption2).padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
            }
            // La más reciente, abajo, junto a la mascota.
            ForEach(shown.reversed()) { s in
                BubbleView(
                    session: s,
                    onOpen: { open(s) },
                    onReply: { opt in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(opt.message, forType: .string)
                        open(s)
                    },
                    onDismiss: { dismissed[s.id] = s.updatedAt }
                )
                .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
            }
            PetRenderer(phase: focus?.phase ?? .idle)
                .overlay(alignment: .topTrailing) {
                    if bubbles.count > 1 {
                        Text("\(bubbles.count)").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(4).background(Color.orange, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
                .onTapGesture { if let s = focus { open(s) } }
                .gesture(DragGesture(minimumDistance: 3)
                    .onChanged { _ in onDrag(false) }
                    .onEnded { _ in onDrag(true) })
            statusLine
        }
        .padding(8)
        .frame(width: PetWindowController.size.width, height: PetWindowController.size.height, alignment: .bottom)
        .animation(.spring(duration: 0.3), value: bubbles.map(\.id))
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

    private func open(_ s: ClaudeSession) {
        dismissed[s.id] = s.updatedAt
        monitor.acknowledge(s.id)
        openInClaude(s)
    }
}

/// Panel transparente, sin bordes, siempre encima y arrastrable.
@MainActor
final class PetWindowController {
    static let size = NSSize(width: 300, height: 560)
    private let panel: NSPanel
    private var dragOffset: NSPoint?

    init(monitor: SessionMonitor) {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: PetView(monitor: monitor) { [weak self] ended in
            self?.drag(ended: ended)
        })
        host.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = host
        if panel.setFrameUsingName("ClaudioPet") {
            panel.setFrame(NSRect(origin: panel.frame.origin, size: Self.size), display: false)
        } else {
            resetPosition()
        }
        panel.setFrameAutosaveName("ClaudioPet")
        keepOnScreen()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepOnScreen() }
        }
    }

    /// Zona que ocupa la mascota dentro del panel (abajo y centrada); los globitos van encima.
    private var petRect: NSRect {
        let f = panel.frame
        return NSRect(x: f.midX - 70, y: f.minY + 8, width: 140, height: 70)
    }

    /// Esquina inferior derecha de la pantalla principal.
    func resetPosition() {
        guard let screen = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: screen.maxX - Self.size.width - 20, y: screen.minY + 12))
        panel.saveFrame(usingName: "ClaudioPet")
    }

    /// Si la mascota ha quedado fuera de todas las pantallas (p. ej. al desconectar un monitor),
    /// la mete dentro de la pantalla más cercana o la devuelve a la esquina.
    private func keepOnScreen() {
        let pet = petRect
        let screens = NSScreen.screens.map(\.visibleFrame)
        if screens.contains(where: { $0.contains(pet) }) { return }
        guard let best = screens.max(by: { $0.intersection(pet).area < $1.intersection(pet).area }),
              best.intersection(pet).area > 0 else { resetPosition(); return }
        // Desplaza lo justo para que la mascota quede entera en esa pantalla.
        var dx: CGFloat = 0, dy: CGFloat = 0
        if pet.minX < best.minX { dx = best.minX - pet.minX } else if pet.maxX > best.maxX { dx = best.maxX - pet.maxX }
        if pet.minY < best.minY { dy = best.minY - pet.minY } else if pet.maxY > best.maxY { dy = best.maxY - pet.maxY }
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX + dx, y: panel.frame.minY + dy))
        panel.saveFrame(usingName: "ClaudioPet")
    }

    private func drag(ended: Bool) {
        let mouse = NSEvent.mouseLocation
        if ended {
            dragOffset = nil
            keepOnScreen()
            panel.saveFrame(usingName: "ClaudioPet")
            return
        }
        let offset = dragOffset ?? NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        dragOffset = offset
        panel.setFrameOrigin(NSPoint(x: mouse.x - offset.x, y: mouse.y - offset.y))
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        keepOnScreen()
        panel.orderFrontRegardless()
        UserDefaults.standard.set(true, forKey: "petVisible")
    }

    func hide() {
        panel.orderOut(nil)
        UserDefaults.standard.set(false, forKey: "petVisible")
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
