import SwiftUI

struct DebriefView: View {
    @EnvironmentObject var store: GameStore

    private var seamTitle: String {
        switch store.seam {
        case "rapport":  return "The Lonely Troll"
        case "loophole": return "The Literal Oath"
        default:         return "The Crossing"
        }
    }
    private var seamText: String {
        switch store.seam {
        case "rapport":  return "You befriended him. Three hundred years of loneliness did what no threat ever could."
        case "loophole": return "You out-lawyered his oath. He kept it to the letter \u{2014} and lost the word anyway."
        default:         return "You found your way across the Mossback Bridge."
        }
    }

    var body: some View {
        VStack(spacing: Metrics.s4) {
            Spacer()
            Text("\u{1F5DD}\u{FE0F}").font(.system(size: 56))
            Text("The gate is open.").font(Type.title).foregroundStyle(Palette.ink)

            VStack(spacing: 6) {
                Text("HOW YOU WON").font(Type.label).tracking(2).foregroundStyle(Palette.inkSoft)
                Text(seamTitle).font(Type.h2).foregroundStyle(Palette.amber)
                Text(seamText).font(Type.body).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Metrics.s4)
            .frame(maxWidth: .infinity)
            .background(Palette.paperDeep)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))

            Text("Crossed in \(store.turnsTaken) turn\(store.turnsTaken == 1 ? "" : "s").")
                .font(Type.small).foregroundStyle(Palette.inkSoft)
            Spacer()
            PrimaryButton(title: "Play again") { store.playAgain() }
        }
        .padding(.horizontal, Metrics.s6).padding(.vertical, Metrics.s8)
    }
}
