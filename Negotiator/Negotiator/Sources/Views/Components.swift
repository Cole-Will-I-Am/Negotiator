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
