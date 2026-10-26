import Foundation

/// `Claudio --demo`: chats y uso inventados para hacer capturas sin enseñar datos reales.
enum Demo {
    static let isOn = CommandLine.arguments.contains("--demo")

    static func sessions() -> [ClaudeSession] {
        let now = Date()
        return [
            ClaudeSession(
                id: "demo-1", hostSessionId: nil, name: "Rediseño de la página de inicio", phase: .done,
                summary: "He cambiado la cabecera por una versión más limpia y he reducido el peso de las imágenes un 60 %. La página carga ahora en 1,2 s en móvil.",
                question: "¿Subo los cambios a la rama de pruebas?",
                options: [
                    ReplyOption(label: "Sí, súbelos", message: "Sí, súbelos a la rama de pruebas."),
                    ReplyOption(label: "Antes enséñame la diferencia", message: "Antes enséñame la diferencia."),
                ],
                updatedAt: now),
            ClaudeSession(id: "demo-2", hostSessionId: nil, name: "Migración de la base de datos", phase: .thinking,
                          updatedAt: now.addingTimeInterval(-40)),
            ClaudeSession(id: "demo-3", hostSessionId: nil, name: "Tests del carrito de compra", phase: .writing,
                          updatedAt: now.addingTimeInterval(-90)),
            ClaudeSession(id: "demo-4", hostSessionId: nil, name: "Traducción al inglés de la web", phase: .idle,
                          updatedAt: now.addingTimeInterval(-3600)),
            ClaudeSession(id: "demo-5", hostSessionId: nil, name: "Informe de ventas mensual", phase: .idle,
                          updatedAt: now.addingTimeInterval(-7200)),
        ]
    }

    static func usage() -> (fiveHour: UsageEstimate, weekly: UsageEstimate) {
        let now = Date()
        return (UsageEstimate(percent: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 25 * 60)),
                UsageEstimate(percent: 76, resetsAt: now.addingTimeInterval(3 * 86400 + 5 * 3600)))
    }
}
