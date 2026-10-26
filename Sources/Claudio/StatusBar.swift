import AppKit
import SwiftUI
import Combine

struct UsagePopoverView: View {
    @ObservedObject var monitor: SessionMonitor
    let usage: UsageEstimator
    let onCalibrate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            UsageSection(usage: usage, onCalibrate: onCalibrate)
            Divider().padding(.vertical, 4)
            Text("Chats").font(.headline)
            if monitor.sessions.isEmpty {
                Text("No hay chats recientes.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(monitor.sessions.prefix(10)) { s in
                Button { openInClaude(s); monitor.acknowledge(s.id) } label: {
                    HStack {
                        Text(AsciiFrames.frames(for: s.phase)[0])
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 92, alignment: .leading)
                        Text(s.name).lineLimit(1)
                        Spacer()
                        if s.phase != .idle {
                            Text(s.phase.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.callout)
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}

/// Icono en la barra de menús: al pasar el ratón muestra el uso; al hacer clic, el menú.
@MainActor
final class StatusBarController: NSResponder, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var dropdown: DropdownPanel!
    private let monitor: SessionMonitor
    private let pet: PetWindowController
    private let settings: SettingsWindowController
    private let usage: UsageEstimator
    private let calibration: CalibrationWindowController
    private var closeTimer: Timer?
    private var bag: Set<AnyCancellable> = []

    init(monitor: SessionMonitor, pet: PetWindowController, settings: SettingsWindowController,
         usage: UsageEstimator) {
        self.monitor = monitor
        self.pet = pet
        self.settings = settings
        self.usage = usage
        self.calibration = CalibrationWindowController(usage: usage)
        super.init()

        dropdown = DropdownPanel(content: UsagePopoverView(
            monitor: monitor, usage: usage, onCalibrate: { [weak self] in self?.calibrate() }))

        if let button = item.button {
            button.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
            button.addTrackingArea(NSTrackingArea(rect: .zero,
                                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                                  owner: self, userInfo: nil))
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        monitor.$sessions.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateTitle()
                if let self, self.dropdown.isVisible { self.placeDropdown() }
            }
        }.store(in: &bag)
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateTitle() {
        let glyph: String
        switch monitor.focus?.phase ?? .idle {
        case .idle: glyph = "◕‿◕"
        case .thinking: glyph = "◔_◔"
        case .writing: glyph = "✎"
        case .done: glyph = "◕ヮ◕ !"
        case .needsYou: glyph = "⊙_⊙ ?"
        }
        item.button?.title = glyph
    }

    // MARK: Hover

    override func mouseEntered(with event: NSEvent) {
        closeTimer?.invalidate()
        guard !dropdown.isVisible else { return }
        placeDropdown()
        dropdown.orderFrontRegardless()
    }

    /// Justo debajo del icono, sin salirse de la pantalla.
    private func placeDropdown() {
        guard let button = item.button, let window = button.window else { return }
        let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = dropdown.fittingSize
        var x = icon.midX - size.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        let y = icon.minY - 6 - size.height
        dropdown.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    override func mouseExited(with event: NSEvent) {
        closeTimer?.invalidate()
        closeTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                let mouse = NSEvent.mouseLocation
                let overButton = self.item.button?.window?.frame.insetBy(dx: -2, dy: -2).contains(mouse) ?? false
                let overPopover = self.dropdown.isVisible && self.dropdown.frame.insetBy(dx: -8, dy: -8).contains(mouse)
                if !overButton && !overPopover {
                    self.dropdown.orderOut(nil)
                    t.invalidate()
                }
            }
        }
    }

    // MARK: Menú

    func menuNeedsUpdate(_ menu: NSMenu) {
        dropdown.orderOut(nil)
        menu.removeAllItems()
        let head = NSMenuItem(title: "Uso estimado", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        if usage.calibration == nil {
            menu.addItem(disabled("Sin calibrar"))
        } else {
            if let five = usage.fiveHour { menu.addItem(disabled(usageLine("Sesión 5 h", five))) }
            if let week = usage.weekly { menu.addItem(disabled(usageLine("Semanal", week))) }
        }
        let cal = NSMenuItem(title: "Calibrar con /usage…", action: #selector(calibrate), keyEquivalent: "u")
        cal.target = self
        menu.addItem(cal)
        menu.addItem(.separator())
        let petItem = NSMenuItem(title: "Mostrar mascota", action: #selector(togglePet), keyEquivalent: "")
        petItem.state = pet.isVisible ? .on : .off
        petItem.target = self
        menu.addItem(petItem)
        let resetPet = NSMenuItem(title: "Recolocar mascota", action: #selector(resetPet), keyEquivalent: "")
        resetPet.target = self
        menu.addItem(resetPet)
        let prefs = NSMenuItem(title: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Claudio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func usageLine(_ title: String, _ e: UsageEstimate) -> String {
        let reset = e.resetsAt.map { " · se restablece \(UsageFormat.reset($0))" } ?? ""
        return "\(title): ≈ \(Int(e.percent.rounded())) %\(reset)"
    }

    @objc private func calibrate() {
        dropdown.orderOut(nil)
        calibration.show()
    }

    @objc private func resetPet() {
        pet.resetPosition()
        pet.show()
    }

    @objc private func togglePet() { pet.isVisible ? pet.hide() : pet.show() }
    @objc private func openSettings() { settings.show() }
}

/// Panel flotante con fondo translúcido de menú, para el desplegable del icono.
@MainActor
final class DropdownPanel: NSPanel {
    private let host: NSHostingView<AnyView>

    init<V: View>(content: V) {
        host = NSHostingView(rootView: AnyView(content))
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false

        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 0.5
        blur.layer?.borderColor = NSColor.separatorColor.cgColor
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor),
            host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        contentView = blur
    }

    var fittingSize: NSSize { host.fittingSize }

    override var canBecomeKey: Bool { true }
}
