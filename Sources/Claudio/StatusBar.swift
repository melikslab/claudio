import AppKit
import SwiftUI
import Combine

/// Desplegable al pasar el ratón: los últimos chats.
struct ChatsPopoverView: View {
    @ObservedObject var monitor: SessionMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Últimos chats", "Recent chats")).font(.headline)
            if monitor.sessions.isEmpty {
                Text(L("No hay chats recientes.", "No recent chats.")).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(monitor.sessions.prefix(10)) { s in
                Button { openInClaude(s); monitor.acknowledge(s.id) } label: {
                    HStack {
                        Text(AsciiFrames.still(for: s.phase))
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

/// Icono en la barra de menús: al pasar el ratón muestra los últimos chats; al hacer clic,
/// el menú con las barras de uso y los ajustes.
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

        dropdown = DropdownPanel(content: ChatsPopoverView(monitor: monitor))

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
        case .done: glyph = "◕‿◕ !"
        case .needsYou: glyph = "⊙_⊙ ?"
        }
        item.button?.title = monitor.isSleeping ? "−_− z" : glyph
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
        // Barras de uso dibujadas con SwiftUI dentro del propio menú.
        let usageItem = NSMenuItem()
        let usageView = NSHostingView(rootView: UsageSection(usage: usage)
            .padding(.horizontal, 14).padding(.vertical, 10).frame(width: 360))
        usageView.frame = NSRect(origin: .zero, size: usageView.fittingSize)
        usageItem.view = usageView
        menu.addItem(usageItem)
        let cal = NSMenuItem(title: L("Calibrar con /usage…", "Calibrate with /usage…"), action: #selector(calibrate), keyEquivalent: "u")
        cal.target = self
        menu.addItem(cal)
        menu.addItem(.separator())
        if Demo.isOn {
            let demo = NSMenuItem(title: L("Estado de la mascota (demo)", "Pet state (demo)"), action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let states: [(String, Int)] = [(L("En reposo", "Idle"), 0), (L("Pensando", "Thinking"), 1),
                                           (L("Trabajando", "Working"), 2), (L("Terminado", "Done"), 3),
                                           (L("Te necesita", "Needs you"), 4), (L("Dormida", "Asleep"), -1)]
            for (title, tag) in states {
                let it = NSMenuItem(title: title, action: #selector(setDemoState(_:)), keyEquivalent: "")
                it.tag = tag
                it.target = self
                sub.addItem(it)
            }
            demo.submenu = sub
            menu.addItem(demo)
            menu.addItem(.separator())
        }
        let petItem = NSMenuItem(title: L("Mostrar mascota", "Show pet"), action: #selector(togglePet), keyEquivalent: "")
        petItem.state = pet.isVisible ? .on : .off
        petItem.target = self
        menu.addItem(petItem)
        let resetPet = NSMenuItem(title: L("Recolocar mascota", "Reset pet position"), action: #selector(resetPet), keyEquivalent: "")
        resetPet.target = self
        menu.addItem(resetPet)
        let prefs = NSMenuItem(title: L("Ajustes…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Salir de Claudio", "Quit Claudio"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func calibrate() {
        dropdown.orderOut(nil)
        calibration.show()
    }

    @objc private func resetPet() {
        pet.resetPosition()
        pet.show()
    }

    @objc private func setDemoState(_ sender: NSMenuItem) {
        monitor.setDemoPhase(sender.tag < 0 ? nil : Phase(rawValue: sender.tag))
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
