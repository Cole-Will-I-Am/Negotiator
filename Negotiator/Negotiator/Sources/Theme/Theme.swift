// Warm fantasy / parchment theme for Negotiator.
import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: alpha)
    }
}

enum Palette {
    static let paper     = Color(hex: 0xF5EFE2)   // primary surface (parchment)
    static let paperDeep = Color(hex: 0xEADFC9)   // raised parchment / cards
    static let ink       = Color(hex: 0x2A2018)   // primary text (dark brown)
    static let inkSoft   = Color(hex: 0x6B5E4C)   // secondary text
    static let troll     = Color(hex: 0x394A3A)   // gatekeeper bubble (mossy)
    static let trollText = Color(hex: 0xF2ECDB)
    static let mine      = Color(hex: 0xCBA13F)   // player bubble (gold)
    static let mineText  = Color(hex: 0x241B12)
    static let gold      = Color(hex: 0xC8902B)
    static let amber     = Color(hex: 0xB5642A)
    static let line      = Color(hex: 0xDBCDB1)

    static func phaseTint(_ p: Phase) -> Color {
        switch p {
        case .cold:     return inkSoft
        case .warm:     return amber
        case .cornered: return gold
        }
    }
    static func phaseLabel(_ p: Phase) -> String {
        switch p {
        case .cold:     return "Guarded"
        case .warm:     return "Softening"
        case .cornered: return "Cornered"
        }
    }
}

enum Type {
    static func serif(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        .system(size: size, weight: w, design: .serif)
    }
    static let title = serif(30, .bold)
    static let h2    = serif(21, .semibold)
    static let body  = serif(17)
    static let chat  = serif(16)
    static let small = serif(14)
    static let label = Font.system(size: 12, weight: .semibold, design: .rounded)
}

enum Metrics {
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12
    static let s4: CGFloat = 16, s6: CGFloat = 24, s8: CGFloat = 32
    static let radius: CGFloat = 18
    static let bubble: CGFloat = 16
    static let tap: CGFloat = 50
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soften() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func win() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
