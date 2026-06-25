// Lightweight local persistence: the first-launch onboarding flag and the count of wins.
import Foundation

final class LocalStore {
    private let onboardedKey = "negotiator.hasOnboarded"
    private let winsKey = "negotiator.wins"

    var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: onboardedKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardedKey) }
    }

    var wins: Int {
        get { UserDefaults.standard.integer(forKey: winsKey) }
        set { UserDefaults.standard.set(newValue, forKey: winsKey) }
    }

    // One-time: have we shown the "his mood is your progress meter" hint yet?
    var hasSeenPhaseHint: Bool {
        get { UserDefaults.standard.bool(forKey: "negotiator.phaseHintSeen") }
        set { UserDefaults.standard.set(newValue, forKey: "negotiator.phaseHintSeen") }
    }

    // Cinematics on/off (default ON). object(forKey) so the default is true, not false.
    var cinematicsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "negotiator.cinematics") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "negotiator.cinematics") }
    }
}
