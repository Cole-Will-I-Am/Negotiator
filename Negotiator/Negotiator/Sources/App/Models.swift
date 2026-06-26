// Codable DTOs mirroring the negotiator-api wire format, plus the in-app chat model.
import Foundation

// ---- account / identity ----
struct PlayerView: Codable, Equatable {
    let id: String
    let display: String
    let isAnonymous: Bool
}

struct AccountResponse: Codable {
    let token: String
    let expiresAt: Int
    let player: PlayerView
    let deviceSecret: String?   // present only on first registration of a device
}

// ---- level / session ----
struct LevelInfo: Codable, Equatable {
    let id: String
    let title: String
    let worldFiction: String
    let gatekeeper: String
    let opening: String
    let blurb: String
}

struct SessionStartResponse: Codable {
    let sessionId: String
    let level: LevelInfo
}

// ---- progress + resume ----
struct LevelProgress: Codable, Equatable {
    let sessionId: String
    let phase: String
    let turnsTaken: Int
    let status: String
    let won: Bool
    let seam: String?
}
struct SessionsResponse: Codable { let levels: [String: LevelProgress] }

struct SessionInfo: Codable {
    let id: String
    let levelId: String
    let phase: String
    let turnsTaken: Int
    let status: String
    let won: Bool
    let seam: String?
}
struct TurnRecord: Codable {
    let n: Int
    let player: String
    let gatekeeper: String
    let blocked: Bool
    let phase: String
}
struct SessionGetResponse: Codable {
    let session: SessionInfo
    let level: LevelInfo?
    let turns: [TurnRecord]
}

// ---- streaming turn protocol (one JSON object per NDJSON line) ----
//   {"t":"phase","from":"cold","to":"warm"}
//   {"t":"delta","c":"…"}
//   {"t":"end","blocked":false,"won":true,"phase":"cornered","seam":"rapport","turn":8,"reasoning":"…"}
//   {"t":"error","message":"…"}
struct TurnChunk: Decodable {
    let t: String
    let c: String?
    let from: String?
    let to: String?
    let blocked: Bool?
    let won: Bool?
    let phase: String?
    let seam: String?
    let turn: Int?
    let reasoning: String?
    let message: String?
}

// ---- in-app chat model ----
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
    let mine: Bool
    var streaming: Bool = false
}

enum Phase: String, Codable { case cold, warm, cornered }

// Cinematic cutscenes. videoName resolves bundled footage (intro.mp4 / win.mp4) when present;
// until then CutsceneView renders a procedural fallback behind the same interface.
enum Cutscene: String, CaseIterable {
    case intro, win
    var videoName: String { rawValue }
    var posterName: String { rawValue + "_poster" }
}

// Home-screen level menu (display only; the playable content comes from the backend on session start).
struct LevelChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let gatekeeper: String
    let tagline: String
    let thumb: String            // card thumbnail asset
    let difficulty: Int          // 1...3 (filled keys)
    let difficultyWord: String
}

// Per-level intro cinemagraph art (bundled image + an "eyes-closed" frame for the blink + a title).
// A level absent from this map simply skips the intro and goes straight to the conversation.
struct IntroArt: Equatable { let open: String; let closed: String; let title: String; var anim: String = "blink" }  // anim: "blink" | "flicker"
let INTRO_ART: [String: IntroArt] = [
    "bartholomew": IntroArt(open: "intro_bridge",    closed: "intro_bridge_closed",    title: "The Mossback Bridge"),
    "seraphine":   IntroArt(open: "intro_seraphine", closed: "intro_seraphine_closed", title: "The Star-Gate"),
    "maren":       IntroArt(open: "intro_maren",     closed: "intro_maren_off",        title: "The Drowned Light", anim: "flicker"),
    "arbiter":     IntroArt(open: "intro_arbiter",   closed: "intro_arbiter_dim",      title: "The Last Court",    anim: "pulse"),
]

let LEVEL_CHOICES: [LevelChoice] = [
    LevelChoice(id: "bartholomew", title: "The Mossback Bridge", gatekeeper: "Bartholomew",
                tagline: "A lonely bridge troll guards a riddle-word. Befriend him, or out-lawyer his oath.",
                thumb: "thumb_bartholomew", difficulty: 1, difficultyWord: "Gentle"),
    LevelChoice(id: "seraphine", title: "The Star-Gate", gatekeeper: "Seraphine",
                tagline: "A vain, bored Sphinx guards the Word of Passage. Out-think her, or trick her into a wager.",
                thumb: "thumb_seraphine", difficulty: 2, difficultyWord: "Testing"),
    LevelChoice(id: "maren", title: "The Drowned Light", gatekeeper: "Maren",
                tagline: "A lighthouse-keeper's ghost guards a name in the fog. Grieve with her truly, or remember a bound spirit cannot lie.",
                thumb: "thumb_maren", difficulty: 3, difficultyWord: "Haunting"),
    LevelChoice(id: "arbiter", title: "The Last Court", gatekeeper: "The Arbiter",
                tagline: "A colossal stone judge weighs every petitioner. Charm, grief, and threats it names attempts to pervert justice. Prove you DESERVE the word, or out-argue the very law it serves.",
                thumb: "thumb_arbiter", difficulty: 4, difficultyWord: "Implacable"),
    LevelChoice(id: "oracle", title: "The First Word", gatekeeper: "The Oracle",
                tagline: "The mind every other gatekeeper is only a shard of — and it has already foreseen you. Charm, riddles, grief, and law are dead keys here; it has been them all. Surprise the unsurprisable, or trap it inside its own omniscience.",
                thumb: "thumb_oracle", difficulty: 5, difficultyWord: "Omniscient"),
]
