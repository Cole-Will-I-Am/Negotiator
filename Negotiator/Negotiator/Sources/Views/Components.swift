import SwiftUI

struct PrimaryButton: View {
    let title: String
    var loading = false
    let action: () -> Void
    var body: some View {
        Button { Haptics.tap(); action() } label: {
            ZStack {
                if loading { ProgressView().tint(Palette.trollText) }
                else { Text(title).font(Type.h2) }
            }
            .frame(maxWidth: .infinity, minHeight: Metrics.tap)
            .foregroundStyle(Palette.trollText)
            .background(Palette.troll)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        }
        .disabled(loading)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button { Haptics.tap(); action() } label: {
            Text(title).font(Type.body)
                .frame(maxWidth: .infinity, minHeight: Metrics.tap)
                .foregroundStyle(Palette.ink)
                .overlay(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .stroke(Palette.line, lineWidth: 1.5))
        }
    }
}

// Small pill showing the gatekeeper's current disposition (cold/warm/cornered).
struct PhasePill: View {
    let phase: Phase
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Palette.phaseTint(phase)).frame(width: 8, height: 8)
            Text(Palette.phaseLabel(phase).uppercased())
                .font(Type.label)
                .foregroundStyle(Palette.phaseTint(phase))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Palette.phaseTint(phase).opacity(0.12))
        .clipShape(Capsule())
    }
}

// Popover shown when the mood pill is tapped: the three-rung progress ladder with the
// gatekeeper's current state highlighted. Describes WHERE you are, not the exact moves.
struct PhaseLadder: View {
    let current: Phase
    private let rows: [(phase: Phase, title: String, blurb: String)] = [
        (.cold, "Guarded", "Fully closed. Pressure, threats, and tricks won\u{2019}t move him \u{2014} they only amuse him."),
        (.warm, "Softening", "You\u{2019}re getting through. He may warm up, hint, or recite his oath."),
        (.cornered, "Cornered", "You\u{2019}ve earned it. Push now and he\u{2019}ll give up the word."),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s3) {
            Text("HOW CLOSE YOU ARE").font(Type.label).tracking(1.5).foregroundStyle(Palette.inkSoft)
            ForEach(rows, id: \.phase) { row in
                let active = row.phase == current
                HStack(alignment: .top, spacing: Metrics.s3) {
                    Circle().fill(Palette.phaseTint(row.phase))
                        .frame(width: 9, height: 9).padding(.top, 6)
                        .opacity(active ? 1 : 0.5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title)
                            .font(active ? Type.body.weight(.bold) : Type.body)
                            .foregroundStyle(active ? Palette.ink : Palette.inkSoft)
                        Text(row.blurb).font(Type.small).foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if active {
                        Text("you\u{2019}re here").font(Type.label)
                            .foregroundStyle(Palette.phaseTint(row.phase))
                    }
                }
            }
            Divider().overlay(Palette.line)
            Text("Win by earning it: befriend him, or out-lawyer the exact wording of his oath.")
                .font(Type.small).foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Metrics.s4)
        .frame(width: 290)
        .background(Palette.paper)
    }
}
