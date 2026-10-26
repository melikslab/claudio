import Foundation

/// Idioma de la interfaz: español si el Mac está en español; inglés en cualquier otro caso
/// y siempre en el modo demo (para capturas del README).
enum Lang {
    static let english: Bool = Demo.isOn || !(Locale.preferredLanguages.first?.hasPrefix("es") ?? false)

    /// Para fechas y horas: en la demo, formato inglés; si no, el del sistema.
    static let locale: Locale = Demo.isOn ? Locale(identifier: "en_US") : .current
}

/// Texto de la interfaz en español e inglés.
func L(_ es: String, _ en: String) -> String { Lang.english ? en : es }
