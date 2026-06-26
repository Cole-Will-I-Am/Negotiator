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

// Level select — pick a gatekeeper.
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
            Text("Choose a gate").font(Type.title).foregroundStyle(Palette.ink)
            Text("Each gatekeeper guards a secret. Talk it out of them — every one needs a different key.")
                .font(Type.body).foregroundStyle(Palette.inkSoft)

            ScrollView {
                VStack(spacing: Metrics.s3) {
                    ForEach(LEVEL_CHOICES) { lv in
                        Button { Haptics.tap(); store.approachBridge(lv.id) } label: { LevelCard(level: lv) }
                            .buttonStyle(.plain)
                            .disabled(store.starting)
                    }
                }
                .padding(.vertical, Metrics.s2)
            }

            if let err = store.errorText {
                Text(err).font(Type.small).foregroundStyle(Palette.amber)
            }
            if store.wins > 0 {
                Text("Gates opened: \(store.wins)")
                    .font(Type.small).foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, Metrics.s6)
        .padding(.vertical, Metrics.s8)
        .sheet(isPresented: $showHowTo) { HowToPlayView() }
    }
}

private struct LevelCard: View {
    let level: LevelChoice
    var body: some View {
        HStack(spacing: Metrics.s4) {
            Text(level.glyph).font(.system(size: 38))
                .frame(width: 64, height: 64)
                .background(Palette.troll)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(level.title).font(Type.h2).foregroundStyle(Palette.ink)
                Text(level.gatekeeper.uppercased()).font(Type.label).tracking(1).foregroundStyle(Palette.amber)
                Text(level.tagline).font(Type.small).foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.line)
        }
        .padding(Metrics.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paperDeep)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
    }
}
