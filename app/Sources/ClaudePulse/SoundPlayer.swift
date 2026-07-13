import AppKit

/// Zvuci na tranzicijama (§3.4 Sounds) preko `NSSound(named:)` — sistemski zvuci, zero-dep.
///
/// Odvojeno od notifikacija: kontrolišemo volume i koristimo isti engine za „Preview" u
/// Settings-u. Jaka referenca na tekući `NSSound` da ga ARC ne oslobodi pre kraja reprodukcije.
@MainActor
final class SoundPlayer {
    private var current: NSSound?

    /// Odsviraj zvuk po imenu (npr. „Glass"). Prekida prethodni ako još svira. `volume` ∈ [0, 1].
    func play(named name: String, volume: Double) {
        guard let sound = NSSound(named: name) else {
            AppLog.error("sound not found: \(name)")
            return
        }
        current?.stop()
        sound.volume = Float(max(0, min(1, volume)))
        current = sound
        sound.play()
    }

    /// Odsviraj `doneSound` po tekućim podešavanjima (poštuje master `soundsEnabled`).
    func playDone(settings: Settings) {
        guard settings.soundsEnabled else { return }
        play(named: settings.doneSound, volume: settings.volume)
    }

    /// Odsviraj `waitingSound` po tekućim podešavanjima.
    func playWaiting(settings: Settings) {
        guard settings.soundsEnabled else { return }
        play(named: settings.waitingSound, volume: settings.volume)
    }

    /// Imena sistemskih zvukova iz `/System/Library/Sounds` (za Settings dropdown), sortirana.
    static func availableSounds() -> [String] {
        let dir = URL(fileURLWithPath: "/System/Library/Sounds")
        let names = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "aiff" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
        // Fallback lista ako direktorijum nije čitljiv (defanzivno).
        return (names?.isEmpty == false ? names : nil) ?? ["Glass", "Ping", "Hero", "Submarine", "Pop"]
    }
}
