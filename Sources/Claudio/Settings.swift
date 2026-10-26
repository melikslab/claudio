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
            Section(L("General", "General")) {
                Toggle(L("Abrir Claudio al iniciar el Mac", "Open Claudio at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle(L("Mostrar mascota en el escritorio", "Show pet on the desktop"), isOn: $petVisible)
                    .onChange(of: petVisible) { _, on in on ? pet.show() : pet.hide() }
            }

            Section(L("Cuando Claude termina", "When Claude finishes")) {
                Toggle(L("Avisar", "Alert"), isOn: $notifyDone)
                soundPicker(L("Sonido", "Sound"), selection: $soundDone).disabled(!notifyDone)
            }

            Section(L("Cuando Claude te necesita (permiso o pregunta)", "When Claude needs you (permission or question)")) {
                Toggle(L("Avisar", "Alert"), isOn: $notifyNeedsYou)
                soundPicker(L("Sonido", "Sound"), selection: $soundNeedsYou).disabled(!notifyNeedsYou)
            }

            Section(L("Notificaciones", "Notifications")) {
                Toggle(L("Mostrar notificación del sistema", "Show system notification"), isOn: $systemNotification)
                    .onChange(of: systemNotification) { _, on in
                        if on { notifier.requestAuthorizationIfNeeded() }
                    }
                Toggle(L("Incluir el mensaje de Claude", "Include Claude's message"), isOn: $showSummary).disabled(!systemNotification)
                Toggle(L("Solo si la app de Claude no está delante", "Only when the Claude app is not in front"), isOn: $onlyWhenClaudeInactive)
                if notificationsDenied && systemNotification {
                    HStack {
                        Text(L("macOS tiene bloqueadas las notificaciones de Claudio.", "macOS is blocking Claudio's notifications."))
                            .font(.caption).foregroundStyle(.orange)
                        Button(L("Abrir Ajustes del Sistema", "Open System Settings")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    }
                }
                Button(L("Probar aviso", "Send test alert")) { notifier.sendTest() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .task { await refreshNotificationStatus() }
    }

    private func soundPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(SystemSounds.all, id: \.self) { Text($0 == SystemSounds.none ? L("Ninguno", "None") : $0).tag($0) }
        }
        .onChange(of: selection.wrappedValue) { _, name in SystemSounds.play(name) }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = L("No se pudo cambiar: ", "Could not change it: ") + error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if on, SMAppService.mainApp.status == .requiresApproval {
            loginError = L("Apruébalo en Ajustes del Sistema → General → Ítems de inicio.", "Approve it in System Settings → General → Login Items.")
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
            w.title = L("Ajustes de Claudio", "Claudio Settings")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
