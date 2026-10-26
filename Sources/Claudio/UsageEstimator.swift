import Foundation

/// Calibración tomada de `/usage`: % reales en un momento dado.
struct UsageCalibration: Codable {
    struct Window: Codable {
        var percent: Double
        var resetsAt: Date
    }
    var at: Date
    var fiveHour: Window
    var weekly: Window
    /// Unidades de gasto que equivalen al 100 % de cada ventana.
    var cap5h: Double
    var cap7d: Double
}

struct UsageEstimate {
    var percent: Double
    var resetsAt: Date?
}

/// Estima el % de uso de 5 h y semanal sumando el gasto de todos los chats de Claude Code
/// (~/.claude/projects/**/*.jsonl), con la escala calibrada a mano a partir de `/usage`.
/// Lo que se gasta fuera de este Mac (claude.ai, móvil…) no se ve: por eso conviene recalibrar.
@MainActor
final class UsageEstimator: ObservableObject {
    @Published private(set) var fiveHour: UsageEstimate?
    @Published private(set) var weekly: UsageEstimate?
    @Published private(set) var calibration: UsageCalibration?

    private let scanner = HistoryScanner()
    private var timer: Timer?
    private static let key = "usageCalibration"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key) {
            calibration = try? JSONDecoder().decode(UsageCalibration.self, from: data)
        }
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        Task {
            let events = await scanner.scan()
            recompute(events)
        }
    }

    /// Guarda los % que muestra `/usage` y recalcula la escala.
    func calibrate(fivePercent: Double, fiveResetsAt: Date, weeklyPercent: Double, weeklyResetsAt: Date) {
        Task {
            let events = await scanner.scan()
            let now = Date()
            let used5 = units(events, from: fiveResetsAt.addingTimeInterval(-5 * 3600), to: now)
            let used7 = units(events, from: weeklyResetsAt.addingTimeInterval(-7 * 86400), to: now)
            // Con % muy bajos la escala sale poco fiable: se conserva la anterior.
            let cap5 = fivePercent >= 5 && used5 > 0 ? used5 / (fivePercent / 100) : (calibration?.cap5h ?? 0)
            let cap7 = weeklyPercent >= 3 && used7 > 0 ? used7 / (weeklyPercent / 100) : (calibration?.cap7d ?? 0)
            let cal = UsageCalibration(
                at: now,
                fiveHour: .init(percent: fivePercent, resetsAt: fiveResetsAt),
                weekly: .init(percent: weeklyPercent, resetsAt: weeklyResetsAt),
                cap5h: cap5, cap7d: cap7)
            calibration = cal
            if let data = try? JSONEncoder().encode(cal) { UserDefaults.standard.set(data, forKey: Self.key) }
            recompute(events)
        }
    }

    private func recompute(_ events: [(t: Date, w: Double)]) {
        guard let cal = calibration else { fiveHour = nil; weekly = nil; return }
        let now = Date()

        // 5 h: dentro de la ventana calibrada, % calibrado + lo gastado desde entonces.
        // Después, cada ventana empieza con el primer mensaje tras el reinicio anterior.
        if cal.cap5h > 0 {
            if now < cal.fiveHour.resetsAt {
                let pct = cal.fiveHour.percent + units(events, from: cal.at, to: now) / cal.cap5h * 100
                fiveHour = .init(percent: clamp(pct), resetsAt: cal.fiveHour.resetsAt)
            } else {
                var end = cal.fiveHour.resetsAt
                var start: Date?
                while let first = events.first(where: { $0.t >= end })?.t, first <= now {
                    start = first
                    end = first.addingTimeInterval(5 * 3600)
                    if end > now { break }
                    start = nil
                }
                if let start {
                    fiveHour = .init(percent: clamp(units(events, from: start, to: now) / cal.cap5h * 100), resetsAt: end)
                } else {
                    fiveHour = .init(percent: 0, resetsAt: nil)   // empieza con el próximo mensaje
                }
            }
        }

        // Semanal: el reinicio es fijo, se avanza de 7 en 7 días.
        if cal.cap7d > 0 {
            var reset = cal.weekly.resetsAt
            while reset <= now { reset.addTimeInterval(7 * 86400) }
            let pct: Double
            if reset == cal.weekly.resetsAt {
                pct = cal.weekly.percent + units(events, from: cal.at, to: now) / cal.cap7d * 100
            } else {
                pct = units(events, from: reset.addingTimeInterval(-7 * 86400), to: now) / cal.cap7d * 100
            }
            weekly = .init(percent: clamp(pct), resetsAt: reset)
        }
    }

    private func units(_ events: [(t: Date, w: Double)], from: Date, to: Date) -> Double {
        events.reduce(0) { $1.t >= from && $1.t <= to ? $0 + $1.w : $0 }
    }

    private func clamp(_ v: Double) -> Double { min(max(v, 0), 100) }
}

/// Lee los historiales de forma incremental (solo lo añadido desde la última vez).
actor HistoryScanner {
    private var offsets: [String: UInt64] = [:]
    private var events: [String: (t: Date, w: Double)] = [:]   // por id de mensaje (se repite al hacer streaming)
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func scan() -> [(t: Date, w: Double)] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let horizon = Date().addingTimeInterval(-8 * 86400)
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "jsonl",
                  let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  mtime > horizon else { continue }
            read(url)
        }
        events = events.filter { $0.value.t > horizon }
        return events.values.sorted { $0.t < $1.t }
    }

    private func read(_ url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let start = offsets[url.path] ?? 0
        let size = (try? handle.seekToEnd()) ?? 0
        guard size > start else { offsets[url.path] = min(start, size); return }
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let lastNewline = data.lastIndex(of: 0x0A) else { return }
        offsets[url.path] = start + UInt64(lastNewline - data.startIndex + 1)

        let marker = Data("\"type\":\"assistant\"".utf8)
        for line in data[..<lastNewline].split(separator: 0x0A) where line.range(of: marker) != nil {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let msg = obj["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any],
                  let ts = (obj["timestamp"] as? String).flatMap(iso.date(from:)) else { continue }
            let id = msg["id"] as? String ?? obj["uuid"] as? String ?? UUID().uuidString
            events[id] = (ts, Self.weight(model: msg["model"] as? String ?? "", usage: usage))
        }
    }

    /// Gasto relativo de un mensaje: proporcional al precio de la API de cada modelo y tipo de token.
    static func weight(model: String, usage: [String: Any]) -> Double {
        func n(_ k: String) -> Double { (usage[k] as? NSNumber)?.doubleValue ?? 0 }
        let factor = model.contains("opus") ? 5.0 / 3 : model.contains("haiku") ? 1.0 / 3 : 1
        return factor * (n("input_tokens") + 5 * n("output_tokens")
                         + 1.25 * n("cache_creation_input_tokens") + 0.1 * n("cache_read_input_tokens"))
    }
}
