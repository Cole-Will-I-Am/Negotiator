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
    let glyph: String
}

let LEVEL_CHOICES: [LevelChoice] = [
    LevelChoice(id: "bartholomew", title: "The Mossback Bridge", gatekeeper: "Bartholomew",
                tagline: "A lonely bridge troll guards a riddle-word. Befriend him, or out-lawyer his oath.",
                glyph: "\u{1F319}"),
    LevelChoice(id: "seraphine", title: "The Star-Gate", gatekeeper: "Seraphine",
                tagline: "A vain, bored Sphinx guards the Word of Passage. Out-think her, or trick her into a wager.",
                glyph: "\u{1F981}"),
]
