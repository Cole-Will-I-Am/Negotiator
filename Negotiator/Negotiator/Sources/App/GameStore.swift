// The app's single source of truth: screen routing, the anonymous account, the active
// negotiation, and the streaming turn loop. Mirrors RUNG's GameStore shape.
import SwiftUI

@MainActor
final class GameStore: ObservableObject {
    enum Screen: Equatable { case loading, onboarding, home, conversation, debrief }

    @Published var screen: Screen = .loading
    @Published private(set) var account: PlayerView?
    @Published private(set) var level: LevelInfo?
    @Published var messages: [ChatMessage] = []
    @Published private(set) var gkPhase: Phase = .cold
    @Published private(set) var won = false
    @Published private(set) var seam: String?
    @Published private(set) var turnsTaken = 0
    @Published var sending = false
    @Published var starting = false
    @Published var errorText: String?
    @Published private(set) var wins = 0

    let backend = Backend()
    private let local = LocalStore()
    private var token: String?
    private var sessionId: String?

    init() {
        token = Keychain.get("negotiator.sessionToken")
        wins = local.wins
    }

    func bootstrap() {
        screen = local.hasOnboarded ? .home : .onboarding
        Task { await ensureAccount() }
    }

    func finishOnboarding() {
        local.hasOnboarded = true
        screen = .home
    }

    private func ensureAccount() async {
        let device = Keychain.deviceId()
        let secret = Keychain.get("negotiator.deviceSecret")
        do {
            let resp = try await backend.registerAnon(deviceId: device, deviceSecret: secret)
            token = resp.token
            Keychain.set("negotiator.sessionToken", resp.token)
            if let s = resp.deviceSecret { Keychain.set("negotiator.deviceSecret", s) }
            account = resp.player
        } catch {
            errorText = "Couldn't reach the bridge — check your connection and try again."
        }
    }

    // ---- start a fresh negotiation ----
    func startGame() {
        guard !starting else { return }
        starting = true
        errorText = nil
        Task {
            if token == nil { await ensureAccount() }
            guard let token else { starting = false; return }
            do {
                let resp = try await backend.startSession(token: token)
                level = resp.level
                sessionId = resp.sessionId
                messages = [ChatMessage(text: resp.level.opening, mine: false)]
                gkPhase = .cold; won = false; seam = nil; turnsTaken = 0
                screen = .conversation
            } catch {
                errorText = (error as? BackendError)?.errorDescription ?? "Couldn't start the game."
            }
            starting = false
        }
    }

    // ---- one player turn (streams the gatekeeper) ----
    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending, !won, let token, let sessionId else { return }
        messages.append(ChatMessage(text: text, mine: true))
        let gkIndex = messages.count
        messages.append(ChatMessage(text: "", mine: false, streaming: true))
        sending = true
        errorText = nil
        Task {
            do {
                let bytes = try await backend.turnStream(token: token, sessionId: sessionId, message: text)
                for try await line in bytes.lines {
                    let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !s.isEmpty, let data = s.data(using: .utf8),
                          let chunk = try? JSONDecoder().decode(TurnChunk.self, from: data) else { continue }
                    apply(chunk, gkIndex: gkIndex)
                }
            } catch {
                errorText = (error as? BackendError)?.errorDescription ?? "The bridge went quiet. Try again."
            }
            if gkIndex < messages.count {
                messages[gkIndex].streaming = false
                if messages[gkIndex].text.isEmpty {
                    messages[gkIndex].text = "*Bartholomew harrumphs, lost in thought, and says nothing.*"
                }
            }
            sending = false
        }
    }

    private func apply(_ chunk: TurnChunk, gkIndex: Int) {
        switch chunk.t {
        case "delta":
            if let c = chunk.c, gkIndex < messages.count { messages[gkIndex].text += c }
        case "phase":
            if let to = chunk.to, let p = Phase(rawValue: to) { gkPhase = p }
        case "end":
            if let ph = chunk.phase, let p = Phase(rawValue: ph) { gkPhase = p }
            turnsTaken = chunk.turn ?? turnsTaken
            if chunk.won == true {
                won = true
                seam = chunk.seam
                wins += 1
                local.wins = wins
            }
        case "error":
            errorText = chunk.message
        default:
            break
        }
    }

    func toDebrief() { screen = .debrief }

    func playAgain() {
        messages = []; level = nil; sessionId = nil
        gkPhase = .cold; won = false; seam = nil; turnsTaken = 0
        screen = .home
    }
}
