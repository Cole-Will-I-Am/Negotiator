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
}
