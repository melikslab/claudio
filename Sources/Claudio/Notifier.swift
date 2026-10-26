import AppKit
import UserNotifications

/// Claves de ajustes compartidas entre la ventana de ajustes y el resto de la app.
enum Pref {
    static let notifyDone = "notifyDone"
    static let notifyNeedsYou = "notifyNeedsYou"
    static let systemNotification = "systemNotification"
    static let soundDone = "soundDone"
    static let soundNeedsYou = "soundNeedsYou"
    static let onlyWhenClaudeInactive = "onlyWhenClaudeInactive"
    static let showSummary = "notificationShowsSummary"

    static func register() {
        UserDefaults.standard.register(defaults: [
            notifyDone: true, notifyNeedsYou: true, systemNotification: true,
            soundDone: SystemSounds.none, soundNeedsYou: "Pop",
            onlyWhenClaudeInactive: true, showSummary: true,
        ])
    }
}

/// Sonidos del sistema disponibles (/System/Library/Sounds) más "Ninguno".
enum SystemSounds {
    static let none = "Ninguno"
    static let all: [String] = {
        let dir = URL(fileURLWithPath: "/System/Library/Sounds")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return [none] + names.map { ($0 as NSString).deletingPathExtension }.sorted()
    }()

    static func play(_ name: String) {
        guard name != none else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let defaults = UserDefaults.standard
    private var center: UNUserNotificationCenter? {
        // Sin bundle (p. ej. `swift run`) UNUserNotificationCenter revienta.
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }
    var sessionsProvider: () -> [ClaudeSession] = { [] }

    override init() {
        super.init()
        center?.delegate = self
        requestAuthorizationIfNeeded()
    }

    func requestAuthorizationIfNeeded() {
        guard defaults.bool(forKey: Pref.systemNotification) else { return }
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func alert(_ session: ClaudeSession) {
        let isDone = session.phase == .done
        guard defaults.bool(forKey: isDone ? Pref.notifyDone : Pref.notifyNeedsYou) else { return }
        if defaults.bool(forKey: Pref.onlyWhenClaudeInactive),
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == claudeBundleID { return }

        SystemSounds.play(defaults.string(forKey: isDone ? Pref.soundDone : Pref.soundNeedsYou) ?? SystemSounds.none)

        guard defaults.bool(forKey: Pref.systemNotification), let center else { return }
        let content = UNMutableNotificationContent()
        content.title = isDone ? "✅ \(session.name)" : L("❓ \(session.name) te necesita", "❓ \(session.name) needs you")
        if defaults.bool(forKey: Pref.showSummary) {
            content.body = session.question ?? session.summary ?? ""
        }
        content.userInfo = ["sessionId": session.id]
        center.add(UNNotificationRequest(identifier: session.id, content: content, trigger: nil))
    }

    /// Quita del Centro de notificaciones los avisos de Claudio ya entregados.
    func clearDelivered() {
        center?.removeAllDeliveredNotifications()
    }

    func sendTest() {
        let fake = ClaudeSession(id: "test", hostSessionId: nil, name: "Claudio", phase: .done,
                                 summary: L("Así se verán los avisos cuando Claude termine.", "This is how alerts look when Claude finishes."), question: nil,
                                 updatedAt: Date())
        SystemSounds.play(defaults.string(forKey: Pref.soundDone) ?? SystemSounds.none)
        guard defaults.bool(forKey: Pref.systemNotification), let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "✅ \(fake.name)"
        content.body = fake.summary ?? ""
        center.add(UNNotificationRequest(identifier: "test", content: content, trigger: nil))
    }

    // Clic en la notificación → abre ese chat.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["sessionId"] as? String
        Task { @MainActor in
            openInClaude(self.sessionsProvider().first { $0.id == id })
            completionHandler()
        }
    }

    // Mostrarla aunque Claudio esté "activa".
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
