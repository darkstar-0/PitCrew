import SwiftUI

/// Every color the panel uses. Add a theme by adding one more `static let`
/// below and listing it in `Theme.all`.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let isLight: Bool

    let accent: Color      // fills: progress bar, primary button, pill, badges
    let onAccent: Color    // text drawn on top of `accent`
    let accentInk: Color   // accent used as text or outline on a card (needs contrast)

    let panel: Color       // panel background
    let card: Color        // card background
    let text: Color        // primary text; also tinted for subtle fills and outlines
    let secondary: Color   // status lines, descriptions
    let tertiary: Color    // folder names, pending items

    let terminal: Color      // terminal box background
    let terminalText: Color  // command output
    let terminalInk: Color   // the "$ command" line

    static func == (a: Theme, b: Theme) -> Bool { a.id == b.id }
}

extension Theme {
    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r, green: g, blue: b)
    }

    /// The original look: graphite with a lime accent.
    static let pitLane = Theme(
        id: "pit-lane", name: "Pit Lane", isLight: false,
        accent: rgb(0.84, 0.97, 0.36), onAccent: .black, accentInk: rgb(0.84, 0.97, 0.36),
        panel: Color(white: 0.10), card: Color(white: 0.16),
        text: .white, secondary: Color(white: 0.62), tertiary: Color(white: 0.40),
        terminal: Color(white: 0.07), terminalText: Color(white: 0.80),
        terminalInk: rgb(0.84, 0.97, 0.36)
    )

    /// Light: white cards, lime fills, olive text accents.
    static let daylight = Theme(
        id: "daylight", name: "Daylight", isLight: true,
        accent: rgb(0.68, 0.87, 0.16), onAccent: .black, accentInk: rgb(0.31, 0.48, 0.00),
        panel: Color(white: 0.94), card: .white,
        text: Color(white: 0.10), secondary: Color(white: 0.42), tertiary: Color(white: 0.62),
        terminal: Color(white: 0.13), terminalText: Color(white: 0.82),
        terminalInk: rgb(0.84, 0.97, 0.36)
    )

    /// Navy with an electric cyan accent.
    static let midnight = Theme(
        id: "midnight", name: "Midnight", isLight: false,
        accent: rgb(0.36, 0.86, 1.00), onAccent: rgb(0.02, 0.09, 0.15), accentInk: rgb(0.45, 0.88, 1.00),
        panel: rgb(0.06, 0.08, 0.15), card: rgb(0.11, 0.14, 0.24),
        text: .white, secondary: rgb(0.62, 0.68, 0.80), tertiary: rgb(0.42, 0.47, 0.60),
        terminal: rgb(0.03, 0.05, 0.10), terminalText: rgb(0.78, 0.83, 0.92),
        terminalInk: rgb(0.45, 0.88, 1.00)
    )

    /// Racing red on near-black.
    static let rosso = Theme(
        id: "rosso", name: "Rosso", isLight: false,
        accent: rgb(0.93, 0.20, 0.18), onAccent: .white, accentInk: rgb(1.00, 0.45, 0.40),
        panel: rgb(0.09, 0.07, 0.07), card: rgb(0.16, 0.12, 0.12),
        text: .white, secondary: rgb(0.70, 0.62, 0.60), tertiary: rgb(0.48, 0.42, 0.41),
        terminal: rgb(0.05, 0.04, 0.04), terminalText: rgb(0.85, 0.80, 0.79),
        terminalInk: rgb(1.00, 0.45, 0.40)
    )

    /// Papaya orange on graphite.
    static let papaya = Theme(
        id: "papaya", name: "Papaya", isLight: false,
        accent: rgb(1.00, 0.53, 0.05), onAccent: .black, accentInk: rgb(1.00, 0.62, 0.22),
        panel: Color(white: 0.09), card: Color(white: 0.15),
        text: .white, secondary: Color(white: 0.63), tertiary: Color(white: 0.42),
        terminal: Color(white: 0.06), terminalText: Color(white: 0.80),
        terminalInk: rgb(1.00, 0.62, 0.22)
    )

    /// Light: powder blue with an orange accent.
    static let powder = Theme(
        id: "powder", name: "Powder Blue", isLight: true,
        accent: rgb(0.98, 0.52, 0.12), onAccent: .white, accentInk: rgb(0.82, 0.36, 0.00),
        panel: rgb(0.80, 0.90, 0.97), card: .white,
        text: rgb(0.07, 0.12, 0.20), secondary: rgb(0.34, 0.42, 0.52), tertiary: rgb(0.56, 0.62, 0.70),
        terminal: rgb(0.08, 0.13, 0.22), terminalText: rgb(0.80, 0.86, 0.93),
        terminalInk: rgb(1.00, 0.62, 0.25)
    )

    static let all: [Theme] = [pitLane, daylight, midnight, rosso, papaya, powder]

    /// Stored choice: a theme id, or "auto" (Pit Lane in dark mode, Daylight in light mode).
    static let autoID = "auto"

    static func resolve(_ choice: String, colorScheme: ColorScheme) -> Theme {
        if choice == autoID { return colorScheme == .light ? daylight : pitLane }
        return all.first { $0.id == choice } ?? pitLane
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.pitLane
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
