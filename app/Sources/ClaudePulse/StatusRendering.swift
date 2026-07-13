import AppKit

/// Čiste (bez stanja) pomoćne funkcije za prikaz statusa u menu baru (§3.2/§3.3).
/// Isti mapping stanje→boja/glyph/tekst koriste i ikona i redovi menija → nema dupliranja.
/// Sve funkcije primaju eksplicitne ulaze (stanje + enabled + Date) → bez skrivenih zavisnosti.
enum StatusRendering {

    /// Boja tačke po stanju (§3.2). System boje su dinamičke → auto-adaptacija na light/dark menu bar.
    static func color(for state: SourceState) -> NSColor {
        switch state {
        case .busy: return .systemRed
        case .waiting: return .systemOrange
        case .done: return .systemGreen
        case .inactive: return .secondaryLabelColor
        }
    }

    /// Glyph tačke: `●` za aktivna stanja, `✕` za inactive.
    static func glyph(for state: SourceState) -> String {
        state == .inactive ? "✕" : "●"
    }

    /// Čitljiv naziv stanja (za redove menija, §3.3).
    static func label(for state: SourceState) -> String {
        switch state {
        case .inactive: return "Inactive"
        case .busy: return "Busy"
        case .waiting: return "Waiting"
        case .done: return "Done"
        }
    }

    /// Disabled izvor se renderuje kao `inactive` (§1.2: "or source disabled in settings"),
    /// bez obzira na poslednje sačuvano stanje.
    static func effectiveState(state: SourceState, enabled: Bool) -> SourceState {
        enabled ? state : .inactive
    }

    /// Agregatno stanje za icon-only mod: prioritet busy > waiting > done > inactive (§3.2).
    static func aggregate(_ states: [SourceState]) -> SourceState {
        if states.contains(.busy) { return .busy }
        if states.contains(.waiting) { return .waiting }
        if states.contains(.done) { return .done }
        return .inactive
    }

    /// Kratko prikazno slovo izvora u menu baru (C/W/D).
    static func letter(for source: Source) -> String {
        String(source.rawValue.prefix(1)).uppercased()
    }

    /// Pun naziv izvora za redove menija (§3.3).
    static func displayName(for source: Source) -> String {
        switch source {
        case .code: return "Claude Code"
        case .web: return "Browser"
        case .desktop: return "Desktop"
        }
    }

    /// Compact naslov `C● W● D✕`: slova u `.labelColor` (dinamičko), tačke u boji stanja (§3.2).
    /// `effectiveStates` mora biti već propušteno kroz `effectiveState(state:enabled:)`.
    static func compactTitle(letters: [(letter: String, state: SourceState)]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let letterFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        for (index, item) in letters.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "  "))
            }
            result.append(NSAttributedString(
                string: item.letter,
                attributes: [.foregroundColor: NSColor.labelColor, .font: letterFont]
            ))
            result.append(NSAttributedString(
                string: glyph(for: item.state),
                attributes: [.foregroundColor: color(for: item.state), .font: letterFont]
            ))
        }
        return result
    }

    /// Icon-only naslov: jedna tačka u boji agregatnog stanja (§3.2).
    static func iconOnlyTitle(state: SourceState) -> NSAttributedString {
        NSAttributedString(
            string: glyph(for: state),
            attributes: [
                .foregroundColor: color(for: state),
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            ]
        )
    }

    /// Kompaktno relativno vreme (§3.3 "2m ago"): `<60s` → "just now", `<60m` → "Nm ago", inače "Nh ago".
    static func relativeTime(from date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}
