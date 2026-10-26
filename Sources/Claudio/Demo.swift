import Foundation

/// `Claudio --demo`: chats y uso inventados, en inglés, para hacer capturas sin enseñar datos reales.
enum Demo {
    static let isOn = CommandLine.arguments.contains("--demo")

    static func sessions() -> [ClaudeSession] {
        let now = Date()
        return [
            ClaudeSession(
                id: "demo-1", hostSessionId: nil, name: "Homepage redesign", phase: .done,
                summary: "I replaced the header with a cleaner version and cut image weight by 60%. The page now loads in 1.2 s on mobile.",
                question: "Should I push the changes to the staging branch?",
                options: [
                    ReplyOption(label: "Yes, push them", message: "Yes, push them to the staging branch."),
                    ReplyOption(label: "Show me the diff first", message: "Show me the diff first."),
                ],
                updatedAt: now),
            ClaudeSession(id: "demo-2", hostSessionId: nil, name: "Database migration", phase: .thinking,
                          updatedAt: now.addingTimeInterval(-40)),
            ClaudeSession(id: "demo-3", hostSessionId: nil, name: "Shopping cart tests", phase: .writing,
                          updatedAt: now.addingTimeInterval(-90)),
            ClaudeSession(id: "demo-4", hostSessionId: nil, name: "Website translation", phase: .idle,
                          updatedAt: now.addingTimeInterval(-3600)),
            ClaudeSession(id: "demo-5", hostSessionId: nil, name: "Monthly sales report", phase: .idle,
                          updatedAt: now.addingTimeInterval(-7200)),
        ]
    }

    static func usage() -> (fiveHour: UsageEstimate, weekly: UsageEstimate) {
        let now = Date()
        return (UsageEstimate(percent: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 25 * 60)),
                UsageEstimate(percent: 76, resetsAt: now.addingTimeInterval(3 * 86400 + 5 * 3600)))
    }
}
