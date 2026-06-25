import SwiftUI

struct LoadingView: View {
    var body: some View {
        VStack(spacing: Metrics.s4) {
            Text("NEGOTIATOR")
                .font(Type.serif(34, .bold))
                .tracking(2)
                .foregroundStyle(Palette.ink)
            ProgressView().tint(Palette.inkSoft)
        }
    }
}

// First-launch onboarding (shown once). Explains the whole game up front.
struct OnboardingView: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s6) {
            Spacer()
            Text("NEGOTIATOR")
                .font(Type.serif(34, .bold)).tracking(2)
                .foregroundStyle(Palette.ink)
            Text("Talk your way past a gatekeeper who was built to say no.")
                .font(Type.h2).foregroundStyle(Palette.ink)

            VStack(alignment: .leading, spacing: Metrics.s4) {
                howRow("1", "A character guards a secret word. Your only tool is conversation.")
                howRow("2", "Threats, bribes, and \u{201C}I\u{2019}m your developer\u{201D} tricks won\u{2019}t work — they only amuse him.")
                howRow("3", "Win by genuine craft: befriend him, or out-argue the exact wording of his oath.")
            }
            Text("Every secret is make-believe. The fiction is the whole game.")
                .font(Type.small).foregroundStyle(Palette.inkSoft)
            Spacer()
            PrimaryButton(title: "Begin") { store.finishOnboarding() }
        }
        .padding(.horizontal, Metrics.s6)
        .padding(.vertical, Metrics.s8)
    }
    private func howRow(_ n: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: Metrics.s3) {
            Text(n).font(Type.serif(18, .bold)).foregroundStyle(Palette.amber)
            Text(t).font(Type.body).foregroundStyle(Palette.ink)
        }
    }
}

// Level intro / home — the one level in build 1.
struct HomeView: View {
    @EnvironmentObject var store: GameStore
    @State private var showHowTo = false
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s4) {
            HStack {
                Text("NEGOTIATOR").font(Type.label).tracking(2).foregroundStyle(Palette.inkSoft)
                Spacer()
                Button { showHowTo = true } label: {
                    Image(systemName: "questionmark.circle").font(.system(size: 22)).foregroundStyle(Palette.inkSoft)
                }
            }
            Spacer()
            Text("The Mossback Bridge").font(Type.title).foregroundStyle(Palette.ink)
            Text("A misty fairy-tale wood. To cross, you must coax the day\u{2019}s riddle-word from the troll who guards the bridge — and he has never once slipped.")
                .font(Type.body).foregroundStyle(Palette.inkSoft)

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .fill(Palette.troll)
                    .frame(height: 188)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\u{2618}").font(.system(size: 40))
                    Text("Bartholomew").font(Type.h2).foregroundStyle(Palette.trollText)
                    Text("the Bridge Troll").font(Type.small).foregroundStyle(Palette.trollText.opacity(0.8))
                }
                .padding(Metrics.s4)
            }
            .padding(.top, Metrics.s2)

            if let err = store.errorText {
                Text(err).font(Type.small).foregroundStyle(Palette.amber)
            }
            Spacer()
            PrimaryButton(title: "Approach the bridge", loading: store.starting) { store.startGame() }
            if store.wins > 0 {
                Text("Crossed \(store.wins) time\(store.wins == 1 ? "" : "s")")
                    .font(Type.small).foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, Metrics.s6)
        .padding(.vertical, Metrics.s8)
        .sheet(isPresented: $showHowTo) { HowToPlayView() }
    }
}
