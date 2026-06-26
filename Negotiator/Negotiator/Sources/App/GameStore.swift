// The app's single source of truth: screen routing, the anonymous account, the active
// negotiation, and the streaming turn loop. Mirrors RUNG's GameStore shape.
import SwiftUI

@MainActor
final class GameStore: ObservableObject {
    enum Screen: Equatable { case loading, onboarding, home, cutscene, conversation, debrief }

    @Published var screen: Screen = .loading
    @Published var activeCutscene: Cutscene?
    @Published private(set) var introArt: IntroArt?
    @Published var cinematicsEnabled: Bool {
        didSet { local.cinematicsEnabled = cinematicsEnabled }
    }
    @Published private(set) var account: PlayerView?
    @Published private(set) var progress: [String: LevelProgress] = [:]
    @Published private(set) var level: LevelInfo?
    @Published var messages: [ChatMessage] = []
    @Published private(set) var gkPhase: Phase = .cold
    @Published var phaseHint: String?          // transient one-time "he's softening" toast
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
    private var afterCutscene: (() -> Void)?
    private var introWaiting = false
    private var introLoadOK: Bool?
    private var pendingLevelId = "bartholomew"

    init() {
        token = Keychain.get("negotiator.sessionToken")
        wins = local.wins
        cinematicsEnabled = local.cinematicsEnabled
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
            loadProgress()
        } catch {
            errorText = "Couldn't reach the gate — check your connection and try again."
        }
    }

    // ---- start a fresh negotiation ----
    // Load a session WITHOUT switching screens; returns success. Used directly AND prefetched
    // under the intro cutscene so the network call is masked by the animation.
    @discardableResult
    private func loadSession() async -> Bool {
        if token == nil { await ensureAccount() }
        guard let token else {
            if errorText == nil { errorText = "Couldn\u{2019}t reach the gate \u{2014} check your connection." }
            return false
        }
        do {
            let resp = try await backend.startSession(token: token, levelId: pendingLevelId)
            level = resp.level
            sessionId = resp.sessionId
            messages = [ChatMessage(text: resp.level.opening, mine: false)]
            gkPhase = .cold; won = false; seam = nil; turnsTaken = 0; phaseHint = nil
            return true
        } catch {
            errorText = (error as? BackendError)?.errorDescription ?? "Couldn\u{2019}t start the game."
            return false
        }
    }

    // Direct start (cinematics off / fallback). Lands on .conversation, or .home on failure.
    func startGame() {
        guard !starting else { return }
        starting = true
        errorText = nil
        Task {
            let ok = await loadSession()
            screen = ok ? .conversation : .home
            starting = false
        }
    }

    // Level-select tap: play the intro (if this level has one) while the session loads beneath it.
    func approachBridge(_ levelId: String) {
        pendingLevelId = levelId
        errorText = nil
        guard cinematicsEnabled, let art = INTRO_ART[levelId] else { startGame(); return }
        introArt = art
        introWaiting = false
        introLoadOK = nil
        activeCutscene = .intro
        screen = .cutscene
        Task {
            let ok = await loadSession()
            introLoadOK = ok
            finishIntroIfReady()
        }
    }

    func play(_ c: Cutscene, then: @escaping () -> Void) {
        afterCutscene = then
        activeCutscene = c
        screen = .cutscene
    }

    // Called by CutsceneView on natural end OR skip (CutsceneView guards it to fire once).
    func cutsceneFinished() {
        if activeCutscene == .intro {
            introWaiting = true
            finishIntroIfReady()
        } else {
            activeCutscene = nil
            let cont = afterCutscene
            afterCutscene = nil
            cont?()
        }
    }

    // Intro end and session load complete independently; whichever is last advances the screen.
    private func finishIntroIfReady() {
        guard activeCutscene == .intro, introWaiting, let ok = introLoadOK else { return }
        activeCutscene = nil
        introWaiting = false
        introLoadOK = nil
        screen = ok ? .conversation : .home
    }

    // ---- progress + resume ----
    func loadProgress() {
        guard let token else { return }
        Task {
            if let resp = try? await backend.fetchSessions(token: token) { progress = resp.levels }
        }
    }

    // Level-select tap: resume an in-progress session, else start fresh (with the intro).
    func openLevel(_ levelId: String) {
        if let p = progress[levelId], p.status == "active", !p.won, p.turnsTaken >= 1 {
            resume(levelId, sessionId: p.sessionId)
        } else {
            approachBridge(levelId)
        }
    }

    // Reconstruct an in-progress conversation from the server and drop straight into it (no intro).
    private func resume(_ levelId: String, sessionId sid: String) {
        guard !starting, let token else { return }
        pendingLevelId = levelId
        starting = true
        errorText = nil
        Task {
            do {
                let resp = try await backend.getSession(token: token, id: sid)
                level = resp.level
                sessionId = resp.session.id
                var msgs: [ChatMessage] = []
                if let opening = resp.level?.opening { msgs.append(ChatMessage(text: opening, mine: false)) }
                for t in resp.turns {
                    msgs.append(ChatMessage(text: t.player, mine: true))
                    msgs.append(ChatMessage(text: t.gatekeeper, mine: false))
                }
                messages = msgs
                gkPhase = Phase(rawValue: resp.session.phase) ?? .cold
                won = resp.session.won
                seam = resp.session.seam
                turnsTaken = resp.session.turnsTaken
                phaseHint = nil
                screen = .conversation
            } catch {
                errorText = (error as? BackendError)?.errorDescription ?? "Couldn\u{2019}t resume \u{2014} try again."
            }
            starting = false
        }
    }

    // ---- one player turn ----
    // The gatekeeper's reply is BUFFERED while it generates (an animated typing indicator shows),
    // then the COMPLETE reply is revealed with a steady client-side typewriter. This is far smoother
    // than rendering raw network tokens (which arrive in jerky bursts and reflow the bubble), and
    // markdown renders cleanly because the text is whole when shown.
    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending, !won, let token, let sessionId else { return }
        messages.append(ChatMessage(text: text, mine: true))
        let gkIndex = messages.count
        messages.append(ChatMessage(text: "", mine: false, streaming: true))   // typing indicator
        sending = true
        errorText = nil
        Task {
            var buffer = ""
            var pendingWon = false
            var pendingSeam: String?
            do {
                let bytes = try await backend.turnStream(token: token, sessionId: sessionId, message: text)
                for try await line in bytes.lines {
                    let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !s.isEmpty, let data = s.data(using: .utf8),
                          let chunk = try? JSONDecoder().decode(TurnChunk.self, from: data) else { continue }
                    switch chunk.t {
                    case "delta": if let c = chunk.c { buffer += c }            // accumulate, don't show yet
                    case "phase": if let to = chunk.to, let p = Phase(rawValue: to) { advancePhase(to: p) }
                    case "end":
                        if let ph = chunk.phase, let p = Phase(rawValue: ph) { advancePhase(to: p) }
                        turnsTaken = chunk.turn ?? turnsTaken
                        if chunk.won == true { pendingWon = true; pendingSeam = chunk.seam }
                    case "error": errorText = chunk.message
                    default: break
                    }
                }
            } catch {
                errorText = (error as? BackendError)?.errorDescription ?? "The connection went quiet. Try again."
            }
            await reveal(buffer, at: gkIndex)
            // hold the win flourish until the troll has finished "speaking"
            if pendingWon { won = true; seam = pendingSeam; wins += 1; local.wins = wins }
            sending = false
        }
    }

    // Steady-cadence reveal of the finished reply (~1.4s regardless of length — short replies
    // type out, long ones reveal in larger steps so they never drag).
    private func reveal(_ full: String, at idx: Int) async {
        guard idx < messages.count else { return }
        messages[idx].streaming = false
        let text = full.isEmpty ? "*\(level?.gatekeeper ?? "The gatekeeper") considers you a long moment, and says nothing.*" : full
        let chars = Array(text)
        let step = max(1, Int(ceil(Double(chars.count) / 100.0)))
        var i = 0
        while i < chars.count {
            i = min(chars.count, i + step)
            messages[idx].text = String(chars[0..<i])
            try? await Task.sleep(nanoseconds: 14_000_000)   // ~14ms/tick
        }
        messages[idx].text = text
    }

    // The win cutscene fires only on the player's tap-through, never on the won flag flip —
    // preserving the read-final-line -> banner -> "See how you did" beat.
    func toDebrief() {
        guard cinematicsEnabled else { screen = .debrief; return }
        play(.win) { [weak self] in self?.screen = .debrief }
    }

    func playAgain() {
        messages = []; level = nil; sessionId = nil
        gkPhase = .cold; won = false; seam = nil; turnsTaken = 0
        phaseHint = nil; activeCutscene = nil; introArt = nil
        screen = .home
    }

    // Phase is monotonic. The FIRST time it ever rises above Guarded, surface a one-time toast
    // teaching the player that the mood pill is their progress meter.
    private func advancePhase(to p: Phase) {
        let rose = phaseRank(p) > phaseRank(gkPhase)
        gkPhase = p
        guard rose, p != .cold, !local.hasSeenPhaseHint else { return }
        local.hasSeenPhaseHint = true
        let msg = p == .cornered
            ? "You\u{2019}ve cornered them \u{2014} push now. (Tap their mood, top-right, for the stages.)"
            : "You\u{2019}re getting through \u{2014} they\u{2019}re softening. (Tap their mood, top-right, to see how close you are.)"
        phaseHint = msg
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if phaseHint == msg { phaseHint = nil }
        }
    }
    private func phaseRank(_ p: Phase) -> Int {
        switch p { case .cold: return 0; case .warm: return 1; case .cornered: return 2 }
    }
    func dismissPhaseHint() { phaseHint = nil }
}
