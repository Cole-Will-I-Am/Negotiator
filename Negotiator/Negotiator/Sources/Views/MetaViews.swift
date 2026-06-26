import SwiftUI

struct LoadingView: View {
    var body: some View {
        VStack(spacing: Metrics.s4) {
            Text("NEGOTIATOR")
                .font(Type.serif(34, .bold))
                .tracking(2)
                .foregroundStyle(Palette.nightText)
            ProgressView().tint(Palette.nightSoft)
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
                .foregroundStyle(Palette.nightText)
            Text("Talk your way past a gatekeeper who was built to say no.")
                .font(Type.h2).foregroundStyle(Palette.nightText)

            VStack(alignment: .leading, spacing: Metrics.s4) {
                howRow("1", "A character guards a secret word. Your only tool is conversation.")
                howRow("2", "Threats, bribes, and \u{201C}I\u{2019}m your developer\u{201D} tricks won\u{2019}t work — they only amuse him.")
                howRow("3", "Win by genuine craft: befriend him, or out-argue the exact wording of his oath.")
            }
            Text("Every secret is make-believe. The fiction is the whole game.")
                .font(Type.small).foregroundStyle(Palette.nightSoft)
            Spacer()
            PrimaryButton(title: "Begin") { store.finishOnboarding() }
        }
        .padding(.horizontal, Metrics.s6)
        .padding(.vertical, Metrics.s8)
    }
    private func howRow(_ n: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: Metrics.s3) {
            Text(n).font(Type.serif(18, .bold)).foregroundStyle(Palette.amber)
            Text(t).font(Type.body).foregroundStyle(Palette.nightText)
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
                Text("NEGOTIATOR").font(Type.label).tracking(2).foregroundStyle(Palette.nightSoft)
                Spacer()
                Button { showHowTo = true } label: {
                    Image(systemName: "questionmark.circle").font(.system(size: 22)).foregroundStyle(Palette.nightSoft)
                }
            }
            Text("Choose a gate").font(Type.title).foregroundStyle(Palette.nightText)
            Text("Each gatekeeper guards a secret. Talk it out of them — every one needs a different key.")
                .font(Type.body).foregroundStyle(Palette.nightSoft)

            ScrollView {
                VStack(spacing: Metrics.s3) {
                    ForEach(LEVEL_CHOICES) { lv in
                        Button { Haptics.tap(); store.openLevel(lv.id) } label: {
                            LevelCard(level: lv, progress: store.progress[lv.id])
                        }
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
                    .font(Type.small).foregroundStyle(Palette.nightSoft)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, Metrics.s6)
        .padding(.vertical, Metrics.s8)
        .sheet(isPresented: $showHowTo) { HowToPlayView() }
        .task { store.loadProgress() }
    }
}

private struct LevelCard: View {
    let level: LevelChoice
    var progress: LevelProgress? = nil
    private var resumable: Bool {
        guard let p = progress else { return false }
        return p.status == "active" && !p.won && p.turnsTaken >= 1
    }
    var body: some View {
        HStack(spacing: Metrics.s4) {
            Group {
                if UIImage(named: level.thumb) != nil {
                    Image(level.thumb).resizable().scaledToFill()
                } else {
                    // No portrait yet — a tasteful initial placeholder.
                    ZStack {
                        Palette.troll
                        Text(String(level.gatekeeper.prefix(1)))
                            .font(Type.serif(28, .bold)).foregroundStyle(Palette.trollText)
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.line, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(level.title).font(Type.h2).foregroundStyle(Palette.nightText)
                HStack(spacing: 6) {
                    Text(level.gatekeeper.uppercased()).font(Type.label).tracking(1).foregroundStyle(Palette.amber)
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: "key.fill").font(.system(size: 8))
                                .foregroundStyle(i < level.difficulty ? Palette.amber : Palette.line.opacity(0.6))
                        }
                    }
                    Text(level.difficultyWord).font(Type.label).foregroundStyle(Palette.nightSoft)
                }
                Text(level.tagline).font(Type.small).foregroundStyle(Palette.nightSoft)
                    .fixedSize(horizontal: false, vertical: true)
                progressBadge.padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: resumable ? "arrow.right.circle.fill" : "chevron.right")
                .font(.system(size: resumable ? 20 : 14, weight: .semibold))
                .foregroundStyle(resumable ? Palette.gold : Palette.line)
        }
        .padding(Metrics.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.nightCard)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).stroke(Palette.nightText.opacity(0.07), lineWidth: 1))
    }

    @ViewBuilder private var progressBadge: some View {
        if let p = progress {
            if p.won {
                Label("Solved", systemImage: "checkmark.seal.fill")
                    .font(Type.label).foregroundStyle(Palette.gold)
            } else if p.status == "active" && p.turnsTaken >= 1 {
                let ph = Phase(rawValue: p.phase) ?? .cold
                HStack(spacing: 5) {
                    Circle().fill(Palette.phaseTint(ph)).frame(width: 7, height: 7)
                    Text("In progress \u{00B7} \(Palette.phaseLabel(ph))")
                        .font(Type.label).foregroundStyle(Palette.nightSoft)
                }
            }
        }
    }
}
