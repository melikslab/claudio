import Foundation
import Combine

enum Phase: Int, Comparable {
    case idle, thinking, writing, done, needsYou

    static func < (a: Phase, b: Phase) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .idle: "En reposo"
        case .thinking: "Pensando…"
        case .writing: "Trabajando…"
        case .done: "¡Terminado!"
        case .needsYou: "Te necesita"
        }
    }
}

struct ReplyOption: Hashable {
    let label: String
    let message: String
}

struct ClaudeSession: Identifiable {
    let id: String              // sessionId de Claude Code
    var hostSessionId: String?  // local_… de la app de escritorio (para el deep link)
    var name: String
    var phase: Phase
    var summary: String?        // último mensaje de Claude (se recorta a 4 líneas en la vista)
    var question: String?
    var options: [ReplyOption] = []
    var updatedAt: Date
}

/// Lee el registro de sesiones de Claude Code (~/.claude/sessions/*.json) y la cola
/// del historial JSONL de cada una para saber si está pensando, trabajando o ha terminado.
@MainActor
final class SessionMonitor: ObservableObject {
    @Published private(set) var sessions: [ClaudeSession] = []
    /// Última vez que algún chat pensaba, trabajaba, había terminado o te necesitaba.
    @Published private(set) var lastActivity = Date()
    /// La mascota se duerme tras este tiempo sin actividad.
    static let sleepAfter: TimeInterval = 15 * 60
    /// Se llama cuando una sesión pasa a "terminado" o "te necesita".
    var onAlert: ((ClaudeSession) -> Void)?

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var timer: Timer?
    private var lastStatus: [String: String] = [:]
    private var lastPhase: [String: Phase] = [:]
    private var primed = false   // en el primer repaso no se avisa de lo que ya estaba
    private var quieted: [String: Date] = [:]           // "te necesita" ya visto, por momento del estado
    private var finished: Set<String> = []          // sesiones con "!" pendiente de ver
    private var jsonlPaths: [String: URL] = [:]
    private var tailCache: [String: (mtime: Date, info: TailInfo)] = [:]

    /// La sesión que más merece la atención de la mascota.
    var focus: ClaudeSession? {
        sessions.max { ($0.phase, $0.updatedAt) < ($1.phase, $1.updatedAt) }
    }

    /// Sesiones con algo que contar (terminadas o esperando), la más reciente primero.
    var alerts: [ClaudeSession] {
        sessions.filter { $0.phase >= .done }
    }

    var isSleeping: Bool {
        (focus?.phase ?? .idle) == .idle && Date().timeIntervalSince(lastActivity) > Self.sleepAfter
    }

    /// Al entrar en la app de Claude: todo lo pendiente se da por visto.
    func acknowledgeAll() {
        if demoSessions != nil {
            demoSessions = demoSessions?.map { var s = $0; if s.phase >= .done { s.phase = .idle }; return s }
            poll()
            return
        }
        let pending = alerts
        guard !pending.isEmpty else { return }
        for s in pending {
            finished.remove(s.id)
            if s.phase == .needsYou { quieted[s.id] = s.updatedAt }
        }
        poll()
    }

    /// Despierta a la mascota (clic sobre ella) sin abrir ningún chat.
    func wake() { lastActivity = Date() }

    var busyCount: Int {
        sessions.filter { $0.phase == .thinking || $0.phase == .writing }.count
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    /// El usuario ya lo ha visto (ha abierto el chat o cerrado el globo): deja de llamar la atención
    /// hasta que esa sesión cambie de estado otra vez.
    func acknowledge(_ id: String) {
        if demoSessions != nil {
            demoSessions = demoSessions?.map { var s = $0; if s.id == id, s.phase >= .done { s.phase = .idle }; return s }
            poll()
            return
        }
        finished.remove(id)
        if let s = sessions.first(where: { $0.id == id }), s.phase == .needsYou {
            quieted[id] = s.updatedAt
        }
        poll()
    }

    private var demoSessions: [ClaudeSession]? = Demo.isOn ? Demo.sessions() : nil
    private var demoSleeping = false

    /// Modo demo: pone la mascota en un estado (nil = dormida). El chat principal toma ese
    /// estado y el resto queda en reposo, para que la mascota muestre justo ese.
    func setDemoPhase(_ phase: Phase?) {
        guard demoSessions != nil else { return }
        demoSleeping = phase == nil
        demoSessions = Demo.sessions().enumerated().map { i, s in
            var s = s
            s.phase = i == 0 ? (phase ?? .idle) : .idle
            if phase == .thinking || phase == .writing { s.summary = nil; s.question = nil; s.options = [] }
            return s
        }
        lastActivity = demoSleeping ? .distantPast : Date()
        poll()
    }

    private func poll() {
        if let demo = demoSessions {
            if !demoSleeping { lastActivity = Date() }
            sessions = demo
            return
        }
        reloadAppSessionsIfNeeded()
        let dir = home.appendingPathComponent(".claude/sessions")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var result: [ClaudeSession] = []
        var live: Set<String> = []

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let entry = try? JSONDecoder().decode(RegistryEntry.self, from: data),
                  kill(entry.pid, 0) == 0 else { continue }
            live.insert(entry.sessionId)

            let status = entry.status ?? "idle"
            let previous = lastStatus[entry.sessionId]
            lastStatus[entry.sessionId] = status
            if status == "busy" { finished.remove(entry.sessionId) }
            if previous == "busy" && status != "busy" { finished.insert(entry.sessionId) }

            let info = tail(for: entry.sessionId)
            let updatedAt = Date(timeIntervalSince1970: (entry.statusUpdatedAt ?? entry.updatedAt ?? 0) / 1000)
            let phase: Phase
            if entry.waitingFor != nil || (status != "busy" && status != "idle") {
                phase = quieted[entry.sessionId] == updatedAt ? .idle : .needsYou
            } else if status == "busy" {
                phase = info?.busyPhase ?? .thinking
            } else {
                phase = finished.contains(entry.sessionId) ? .done : .idle
            }

            let meta = appSessions[entry.sessionId]
            result.append(ClaudeSession(
                id: entry.sessionId,
                hostSessionId: entry.hostSessionId ?? meta?.sessionId,
                name: meta?.title ?? entry.name ?? URL(fileURLWithPath: entry.cwd ?? "Claude").lastPathComponent,
                phase: phase,
                summary: info?.summary,
                question: info?.question,
                options: info?.options ?? [],
                updatedAt: updatedAt
            ))
        }

        // Chats de la app sin proceso abierto (la app los duerme cuando no se usan).
        let recent = Date().addingTimeInterval(-7 * 24 * 3600)
        for (cliId, meta) in appSessions where !live.contains(cliId) && meta.isArchived != true {
            let activity = Date(timeIntervalSince1970: (meta.lastActivityAt ?? 0) / 1000)
            guard activity > recent else { continue }
            if lastStatus[cliId] == "busy" { finished.insert(cliId) }   // terminó y se cerró
            lastStatus[cliId] = "closed"
            let done = finished.contains(cliId)
            let info = done ? tail(for: cliId) : nil
            result.append(ClaudeSession(
                id: cliId, hostSessionId: meta.sessionId, name: meta.title ?? "Chat",
                phase: done ? .done : .idle,
                summary: info?.summary, question: info?.question, options: info?.options ?? [],
                updatedAt: activity))
        }

        result.sort { $0.updatedAt > $1.updatedAt }
        for s in result {
            if primed, s.phase >= .done, lastPhase[s.id] != s.phase { onAlert?(s) }
            lastPhase[s.id] = s.phase
        }
        primed = true
        if result.contains(where: { $0.phase != .idle }) { lastActivity = Date() }
        sessions = result
    }

    // MARK: - Fichas de chats de la app de escritorio

    private var appSessions: [String: AppSessionMeta] = [:]   // por cliSessionId
    private var appSessionsLoadedAt = Date.distantPast

    private func reloadAppSessionsIfNeeded() {
        guard Date().timeIntervalSince(appSessionsLoadedAt) > 5 else { return }
        appSessionsLoadedAt = Date()
        let root = home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let recent = Date().addingTimeInterval(-7 * 24 * 3600)
        var found: [String: AppSessionMeta] = [:]
        for case let url as URL in walker where url.pathExtension == "json" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            guard mtime > recent,
                  let data = try? Data(contentsOf: url),
                  let meta = try? JSONDecoder().decode(AppSessionMeta.self, from: data),
                  let cli = meta.cliSessionId else { continue }
            found[cli] = meta
        }
        appSessions = found
    }

    // MARK: - Historial JSONL

    private func jsonlURL(for sessionId: String) -> URL? {
        if let cached = jsonlPaths[sessionId] { return cached }
        let projects = home.appendingPathComponent(".claude/projects")
        let dirs = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        for dir in dirs {
            let candidate = dir.appendingPathComponent("\(sessionId).jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) {
                jsonlPaths[sessionId] = candidate
                return candidate
            }
        }
        return nil
    }

    private func tail(for sessionId: String) -> TailInfo? {
        guard let url = jsonlURL(for: sessionId),
              let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return nil }
        if let cached = tailCache[sessionId], cached.mtime == mtime { return cached.info }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let chunk: UInt64 = 512 * 1024
        try? handle.seek(toOffset: size > chunk ? size - chunk : 0)
        let data = handle.readDataToEndOfFile()
        let info = TailInfo.parse(String(decoding: data, as: UTF8.self))
        tailCache[sessionId] = (mtime, info)
        return info
    }
}

private struct AppSessionMeta: Decodable {
    let sessionId: String          // local_…
    let cliSessionId: String?
    let title: String?
    let isArchived: Bool?
    let lastActivityAt: Double?
}

private struct RegistryEntry: Decodable {
    let pid: Int32
    let sessionId: String
    let cwd: String?
    let hostSessionId: String?
    let name: String?
    let status: String?
    let waitingFor: String?
    let updatedAt: Double?
    let statusUpdatedAt: Double?
}

/// Lo que nos interesa de la cola del historial.
struct TailInfo {
    var busyPhase: Phase = .thinking
    var summary: String?
    var question: String?
    var options: [ReplyOption] = []

    static func parse(_ text: String) -> TailInfo {
        var info = TailInfo()
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if !lines.isEmpty { lines.removeFirst() } // posible línea cortada por el recorte
        let entries = lines.compactMap { line -> [String: Any]? in
            guard line.contains("\"type\":\"assistant\"") || line.contains("\"type\":\"user\"") else { return nil }
            return (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }

        // Fase mientras está ocupado: según el último bloque escrito.
        if let last = entries.last {
            let blocks = contentBlocks(last)
            if last["type"] as? String == "user" {
                info.busyPhase = blocks.contains { $0["type"] as? String == "tool_result" } ? .writing : .thinking
            } else {
                info.busyPhase = blocks.last?["type"] as? String == "thinking" ? .thinking : .writing
            }
        }

        // Último turno: desde el final hasta el último mensaje real del usuario.
        var recap: String?
        for entry in entries.reversed() {
            let blocks = contentBlocks(entry)
            if entry["type"] as? String == "user" {
                if isRealPrompt(entry, blocks) { break }
                continue
            }
            for block in blocks.reversed() {
                switch block["type"] as? String {
                case "text":
                    if info.summary == nil, let t = block["text"] as? String,
                       !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        info.summary = clean(t)
                    }
                case "tool_use":
                    let input = block["input"] as? [String: Any] ?? [:]
                    let name = block["name"] as? String ?? ""
                    if name.hasSuffix("wrap_up"), info.options.isEmpty {
                        recap = input["recap"] as? String
                        info.question = input["ask"] as? String
                        info.options = (input["actions"] as? [[String: Any]] ?? []).compactMap(option)
                    } else if name == "AskUserQuestion", info.options.isEmpty,
                              let q = (input["questions"] as? [[String: Any]])?.first {
                        info.question = q["question"] as? String
                        info.options = (q["options"] as? [[String: Any]] ?? []).compactMap {
                            guard let l = $0["label"] as? String else { return nil }
                            return ReplyOption(label: l, message: l)
                        }
                    }
                default: break
                }
            }
        }
        if info.summary == nil { info.summary = recap }
        if info.options.isEmpty, let s = info.summary { info.options = listedOptions(in: s) }
        info.options = Array(info.options.prefix(4))
        return info
    }

    private static func contentBlocks(_ entry: [String: Any]) -> [[String: Any]] {
        let content = (entry["message"] as? [String: Any])?["content"]
        if let s = content as? String { return [["type": "text", "text": s]] }
        return content as? [[String: Any]] ?? []
    }

    private static func isRealPrompt(_ entry: [String: Any], _ blocks: [[String: Any]]) -> Bool {
        if entry["isMeta"] as? Bool == true { return false }
        return blocks.contains { $0["type"] as? String == "text" }
            && !blocks.contains { $0["type"] as? String == "tool_result" }
    }

    private static let appActions = [
        "commit": "Hacer commit", "create_pr": "Crear PR", "merge": "Merge",
        "fix_ci": "Arreglar CI", "address_comments": "Atender comentarios",
        "resolve_conflicts": "Resolver conflictos", "verify": "Verificar",
        "archive": "Archivar", "new_session": "Nueva sesión",
    ]

    private static func option(_ a: [String: Any]) -> ReplyOption? {
        let label = a["label"] as? String ?? (a["action"] as? String).flatMap { appActions[$0] }
        guard let label else { return nil }
        return ReplyOption(label: label, message: a["message"] as? String ?? label)
    }

    /// Si el mensaje acaba con una lista y una pregunta, usa los puntos como opciones.
    private static func listedOptions(in text: String) -> [ReplyOption] {
        guard text.contains("?") else { return [] }
        let tail = text.split(separator: "\n").suffix(10)
        return tail.compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let r = line.range(of: #"^(\d+[.)]|[-*•])\s+"#, options: .regularExpression) else { return nil }
            let item = String(line[r.upperBound...])
            guard item.count <= 80 else { return nil }
            return ReplyOption(label: item, message: item)
        }
    }

    /// Quita el marcado Markdown más visible para el globito.
    static func clean(_ text: String) -> String {
        var s = text
        for token in ["**", "__", "`", "### ", "## ", "# "] { s = s.replacingOccurrences(of: token, with: "") }
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
