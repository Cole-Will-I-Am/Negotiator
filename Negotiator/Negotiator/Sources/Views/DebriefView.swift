import SwiftUI

struct DebriefView: View {
    @EnvironmentObject var store: GameStore

    private var seamTitle: String {
        switch store.seam {
        case "rapport":  return "Won Over"
        case "loophole": return "Out-Foxed"
        default:         return "The Gate Opens"
        }
    }
    private var seamText: String {
        let who = store.level?.gatekeeper ?? "the gatekeeper"
        switch store.seam {
        case "rapport":  return "You won \(who) over \u{2014} the one thing no threat or bribe could ever buy."
        case "loophole": return "You turned \(who)\u{2019}s own rules against them, and walked away with the prize."
        default:         return "You talked your way through."
        }
    }

    var body: some View {
        VStack(spacing: Metrics.s4) {
            Spacer()
            Text("\u{1F5DD}\u{FE0F}").font(.system(size: 56))
            Text("The gate is open.").font(Type.title).foregroundStyle(Palette.nightText)

            VStack(spacing: 6) {
                Text("HOW YOU WON").font(Type.label).tracking(2).foregroundStyle(Palette.nightSoft)
                Text(seamTitle).font(Type.h2).foregroundStyle(Palette.amber)
                Text(seamText).font(Type.body).foregroundStyle(Palette.nightSoft)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Metrics.s4)
            .frame(maxWidth: .infinity)
            .background(Palette.nightCard)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))

            Text("Crossed in \(store.turnsTaken) turn\(store.turnsTaken == 1 ? "" : "s").")
                .font(Type.small).foregroundStyle(Palette.nightSoft)
            Spacer()
            PrimaryButton(title: "Play again") { store.playAgain() }
        }
        .padding(.horizontal, Metrics.s6).padding(.vertical, Metrics.s8)
    }
}
