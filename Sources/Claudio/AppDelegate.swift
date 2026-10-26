import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = SessionMonitor()
    let usage = UsageEstimator()
    private var notifier: Notifier?
    private var statusBar: StatusBarController?
    private var pet: PetWindowController?
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.register()
        let notifier = Notifier()
        notifier.sessionsProvider = { [monitor] in monitor.sessions }
        monitor.onAlert = { notifier.alert($0) }
        self.notifier = notifier

        let pet = PetWindowController(monitor: monitor)
        let settings = SettingsWindowController(notifier: notifier, pet: pet)
        statusBar = StatusBarController(monitor: monitor, pet: pet, settings: settings, usage: usage)
        self.pet = pet
        self.settings = settings

        monitor.start()
        usage.start()
        // Si entras en la app de Claude, se quitan los globitos y la mascota deja de pedir atención.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [monitor, notifier] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == claudeBundleID else { return }
            MainActor.assumeIsolated {
                monitor.acknowledgeAll()
                notifier.clearDelivered()
            }
        }
        if UserDefaults.standard.object(forKey: "petVisible") as? Bool ?? true {
            pet.show()
        }
    }
}

let claudeBundleID = "com.anthropic.claudefordesktop"

/// Abre la sesión concreta en la app de Claude o, si no hay id, la app sin más.
@MainActor
func openInClaude(_ session: ClaudeSession?) {
    if let host = session?.hostSessionId,
       let url = URL(string: "claude://code/continue?session=\(host)") {
        NSWorkspace.shared.open(url)
        return
    }
    if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeBundleID) {
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }
}
