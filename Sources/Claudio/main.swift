import AppKit

MainActor.assumeIsolated {
    // `Claudio --dump`: imprime lo que la app ve de cada sesión, para depurar.
    if CommandLine.arguments.contains("--dump") {
        let monitor = SessionMonitor()
        monitor.start()
        for s in monitor.sessions {
            print("[\(s.phase.label)] \(s.name) host=\(s.hostSessionId ?? "-")")
            print("  pregunta: \(s.question ?? "-")")
            print("  resumen: \(s.summary?.prefix(160).replacingOccurrences(of: "\n", with: " ⏎ ") ?? "-")")
            print("  opciones: \(s.options.map(\.label))")
        }
        exit(0)
    }
    // `Claudio --parse fichero.jsonl`: muestra qué saldría en el globito para ese historial.
    if let i = CommandLine.arguments.firstIndex(of: "--parse"), i + 1 < CommandLine.arguments.count,
       let text = try? String(contentsOfFile: CommandLine.arguments[i + 1], encoding: .utf8) {
        let info = TailInfo.parse(text)
        print("pregunta: \(info.question ?? "-")\nresumen: \(info.summary ?? "-")\nopciones: \(info.options)")
        exit(0)
    }
    // `Claudio --calibrate 28 2026-10-26T13:10:00Z 21 2026-10-30T07:00:00Z` o `Claudio --usage`.
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--calibrate") ?? args.firstIndex(of: "--usage") {
        let usage = UsageEstimator()
        let iso = ISO8601DateFormatter()
        if args[i] == "--calibrate", args.count >= i + 5,
           let p5 = Double(args[i + 1]), let r5 = iso.date(from: args[i + 2]),
           let p7 = Double(args[i + 3]), let r7 = iso.date(from: args[i + 4]) {
            usage.calibrate(fivePercent: p5, fiveResetsAt: r5, weeklyPercent: p7, weeklyResetsAt: r7)
        } else {
            usage.refresh()
        }
        let deadline = Date().addingTimeInterval(60)
        while (usage.fiveHour == nil || usage.weekly == nil) && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        let line = { (n: String, e: UsageEstimate?) in
            print("\(n): \(e.map { String(format: "%.1f %%", $0.percent) } ?? "-") reinicio: \(e?.resetsAt?.description ?? "-")")
        }
        line("5 h", usage.fiveHour)
        line("Semanal", usage.weekly)
        if let c = usage.calibration { print("escala 5 h: \(Int(c.cap5h)) · semanal: \(Int(c.cap7d))") }
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
