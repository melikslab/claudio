import AppKit
import SwiftUI

struct UsageSection: View {
    @ObservedObject var usage: UsageEstimator
    let onCalibrate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tus límites de uso · estimado").foregroundStyle(.secondary)
                Spacer()
                Button(action: onCalibrate) {
                    HStack(spacing: 4) { Text("Calibrar"); Image(systemName: "arrow.right") }
                }
                .buttonStyle(.plain)
            }
            .font(.callout)

            if usage.calibration == nil {
                Text("Escribe /usage en un chat de Claude y pasa aquí los % con «Calibrar».")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                if let five = usage.fiveHour { UsageBar(title: "Límite de sesión", estimate: five) }
                if let week = usage.weekly { UsageBar(title: "Semanal · todos los modelos", estimate: week) }
            }
        }
    }
}

/// Barra al estilo del panel de uso de Claude: título a la izquierda, reinicio y % a la derecha.
struct UsageBar: View {
    let title: String
    let estimate: UsageEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).lineLimit(1)
                    Spacer(minLength: 12)
                    detail
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).lineLimit(1)
                    HStack { Spacer(); detail }
                }
            }
            .font(.body)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(color)
                        .frame(width: max(geo.size.width * estimate.percent / 100, estimate.percent > 0 ? 6 : 0))
                }
            }
            .frame(height: 6)
            .animation(.easeInOut(duration: 0.4), value: estimate.percent)
        }
    }

    private var detail: some View {
        HStack(spacing: 10) {
            Text(resetText).foregroundStyle(.secondary).lineLimit(1)
            Text("\(Int(estimate.percent.rounded()))%")
                .foregroundStyle(estimate.percent >= 70 ? color : .secondary)
                .monospacedDigit()
        }
    }

    private var resetText: String {
        guard let reset = estimate.resetsAt else { return "Empieza con tu próximo mensaje" }
        return "Se restablece \(UsageFormat.reset(reset))"
    }

    /// Azul normal; naranja al acercarse al límite; rojo cuando casi no queda.
    private var color: Color {
        if estimate.percent >= 90 { return Color(red: 0.89, green: 0.27, blue: 0.24) }
        if estimate.percent >= 70 { return Color(red: 0.95, green: 0.55, blue: 0.20) }
        return Color(red: 0.29, green: 0.50, blue: 0.86)
    }
}

enum UsageFormat {
    /// Como en Claude: "en 1 h 35 min" si falta menos de un día; si no, "el vie, 8:00".
    static func reset(_ date: Date) -> String {
        let left = date.timeIntervalSinceNow
        if left < 24 * 3600 {
            let mins = max(Int(left / 60), 0)
            let h = mins / 60, m = mins % 60
            return h > 0 ? "en \(h) h \(m) min" : "en \(m) min"
        }
        let day = date.formatted(.dateTime.weekday(.abbreviated))
        let time = date.formatted(date: .omitted, time: .shortened)
        return "el \(day), \(time)"
    }
}

struct CalibrationView: View {
    let usage: UsageEstimator
    let onDone: () -> Void

    @State private var fivePercent: Double
    @State private var fiveReset: Date
    @State private var weeklyPercent: Double
    @State private var weeklyReset: Date

    init(usage: UsageEstimator, onDone: @escaping () -> Void) {
        self.usage = usage
        self.onDone = onDone
        let now = Date()
        _fivePercent = State(initialValue: (usage.fiveHour?.percent ?? 0).rounded())
        _fiveReset = State(initialValue: usage.fiveHour?.resetsAt ?? now.addingTimeInterval(5 * 3600))
        _weeklyPercent = State(initialValue: (usage.weekly?.percent ?? 0).rounded())
        _weeklyReset = State(initialValue: usage.weekly?.resetsAt ?? now.addingTimeInterval(7 * 86400))
    }

    var body: some View {
        Form {
            Text("Escribe /usage en cualquier chat de la app de Claude y copia aquí lo que muestra.")
                .font(.callout).foregroundStyle(.secondary)
            Section("Sesión actual (5 h)") {
                percentField(value: $fivePercent)
                DatePicker("Se restablece", selection: $fiveReset, displayedComponents: [.date, .hourAndMinute])
            }
            Section("Semanal · todos los modelos") {
                percentField(value: $weeklyPercent)
                DatePicker("Se restablece", selection: $weeklyReset, displayedComponents: [.date, .hourAndMinute])
            }
            HStack {
                Spacer()
                Button("Cancelar", action: onDone).keyboardShortcut(.cancelAction)
                Button("Guardar") {
                    usage.calibrate(fivePercent: fivePercent, fiveResetsAt: fiveReset,
                                    weeklyPercent: weeklyPercent, weeklyResetsAt: weeklyReset)
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func percentField(value: Binding<Double>) -> some View {
        HStack {
            Text("% usado")
            Spacer()
            TextField("", value: value, format: .number)
                .frame(width: 60).multilineTextAlignment(.trailing)
            Text("%")
        }
    }
}

@MainActor
final class CalibrationWindowController {
    private var window: NSWindow?
    private let usage: UsageEstimator

    init(usage: UsageEstimator) { self.usage = usage }

    func show() {
        // Se recrea cada vez para que arranque con la estimación actual.
        window?.close()
        let w = NSWindow(contentViewController: NSHostingController(rootView: CalibrationView(usage: usage) { [weak self] in
            self?.window?.close()
        }))
        w.title = "Calibrar con /usage"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
