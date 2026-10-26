import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications

struct SettingsView: View {
    let notifier: Notifier
    let pet: PetWindowController

    @AppStorage(Pref.notifyDone) private var notifyDone = true
    @AppStorage(Pref.notifyNeedsYou) private var notifyNeedsYou = true
    @AppStorage(Pref.systemNotification) private var systemNotification = true
    @AppStorage(Pref.soundDone) private var soundDone = SystemSounds.none
    @AppStorage(Pref.soundNeedsYou) private var soundNeedsYou = "Pop"
    @AppStorage(Pref.onlyWhenClaudeInactive) private var onlyWhenClaudeInactive = true
    @AppStorage(Pref.showSummary) private var showSummary = true
    @AppStorage("petVisible") private var petVisible = true

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Abrir Claudio al iniciar el Mac", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Mostrar mascota en el escritorio", isOn: $petVisible)
                    .onChange(of: petVisible) { _, on in on ? pet.show() : pet.hide() }
            }

            Section("Cuando Claude termina") {
                Toggle("Avisar", isOn: $notifyDone)
                soundPicker("Sonido", selection: $soundDone).disabled(!notifyDone)
            }

            Section("Cuando Claude te necesita (permiso o pregunta)") {
                Toggle("Avisar", isOn: $notifyNeedsYou)
                soundPicker("Sonido", selection: $soundNeedsYou).disabled(!notifyNeedsYou)
            }

            Section("Notificaciones") {
                Toggle("Mostrar notificación del sistema", isOn: $systemNotification)
                    .onChange(of: systemNotification) { _, on in
                        if on { notifier.requestAuthorizationIfNeeded() }
                    }
                Toggle("Incluir el mensaje de Claude", isOn: $showSummary).disabled(!systemNotification)
                Toggle("Solo si la app de Claude no está delante", isOn: $onlyWhenClaudeInactive)
                if notificationsDenied && systemNotification {
                    HStack {
                        Text("macOS tiene bloqueadas las notificaciones de Claudio.")
                            .font(.caption).foregroundStyle(.orange)
                        Button("Abrir Ajustes del Sistema") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    }
                }
                Button("Probar aviso") { notifier.sendTest() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .task { await refreshNotificationStatus() }
    }

    private func soundPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(SystemSounds.all, id: \.self) { Text($0).tag($0) }
        }
        .onChange(of: selection.wrappedValue) { _, name in SystemSounds.play(name) }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "No se pudo cambiar: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if on, SMAppService.mainApp.status == .requiresApproval {
            loginError = "Apruébalo en Ajustes del Sistema → General → Ítems de inicio."
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func refreshNotificationStatus() async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsDenied = settings.authorizationStatus == .denied
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let notifier: Notifier
    private let pet: PetWindowController

    init(notifier: Notifier, pet: PetWindowController) {
        self.notifier = notifier
        self.pet = pet
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(notifier: notifier, pet: pet)))
            w.title = "Ajustes de Claudio"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
