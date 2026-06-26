import SwiftUI

// The Ascent Trail — the level-select reimagined as a climb. The Mossback Bridge sits at the
// bottom (earth, moss, water); the path winds upward through each gate to the Oracle's star-wheel
// at the very top. The world ascends earth -> cosmos exactly as the difficulty climbs
// Gentle -> Omniscient. Solved gates light the trail gold behind you; the next gate pulses.
struct TrailMapView: View {
    @EnvironmentObject var store: GameStore

    // index 0 = Bartholomew (bottom) ... last = Oracle (top)
    private let order = LEVEL_CHOICES
    private let spacing: CGFloat = 180
    private let topPad: CGFloat = 150
    private let botPad: CGFloat = 110
    private let fx: [CGFloat] = [0.27, 0.72, 0.27, 0.73, 0.50]   // serpentine

    private var trailHeight: CGFloat { topPad + CGFloat(max(order.count - 1, 0)) * spacing + botPad }
    private func point(_ i: Int, _ w: CGFloat) -> CGPoint {
        CGPoint(x: w * fx[min(i, fx.count - 1)], y: topPad + CGFloat(order.count - 1 - i) * spacing)
    }
    private func solved(_ id: String) -> Bool { store.progress[id]?.won == true }
    private var frontierIndex: Int? { order.firstIndex { !solved($0.id) } }

    // A scattering of fixed stars — denser and brighter toward the cosmic top. (fx, fy, radius, opacity)
    private static let stars: [(CGFloat, CGFloat, CGFloat, Double)] = [
        (0.50, 0.045, 2.6, 1.0), (0.18, 0.03, 1.6, 0.85), (0.80, 0.05, 1.5, 0.8),
        (0.34, 0.08, 1.2, 0.7), (0.66, 0.075, 1.3, 0.75), (0.09, 0.10, 1.6, 0.7),
        (0.91, 0.11, 1.4, 0.65), (0.45, 0.13, 1.1, 0.6), (0.58, 0.16, 1.7, 0.8),
        (0.24, 0.17, 1.3, 0.6), (0.74, 0.19, 1.2, 0.55), (0.12, 0.22, 1.5, 0.6),
        (0.88, 0.24, 1.1, 0.5), (0.40, 0.25, 1.0, 0.5), (0.63, 0.28, 1.4, 0.6),
        (0.30, 0.31, 1.1, 0.45), (0.82, 0.33, 1.2, 0.5), (0.16, 0.35, 1.0, 0.45),
        (0.54, 0.37, 1.3, 0.5), (0.70, 0.41, 1.0, 0.4), (0.38, 0.44, 1.1, 0.4),
        (0.20, 0.47, 0.9, 0.35), (0.86, 0.49, 1.0, 0.35), (0.48, 0.52, 1.0, 0.35),
        (0.62, 0.56, 0.9, 0.3), (0.28, 0.59, 0.9, 0.3), (0.78, 0.62, 0.8, 0.25),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    sky.frame(width: w, height: trailHeight)
                    Canvas { ctx, size in
                        drawGlow(ctx, size)
                        drawStars(ctx, size)
                        drawTrail(ctx, size)
                    }
                    .frame(width: w, height: trailHeight)
                    .allowsHitTesting(false)

                    Text("THE CLIMB")
                        .font(Type.label).tracking(4).foregroundStyle(Palette.nightSoft)
                        .position(x: w * 0.5, y: 96)

                    ForEach(Array(order.enumerated()), id: \.element.id) { idx, lv in
                        let p = point(idx, w)
                        TrailNode(level: lv, progress: store.progress[lv.id], isFrontier: idx == frontierIndex)
                            .position(x: clampX(p.x, w), y: p.y)
                            .onTapGesture { Haptics.tap(); store.openLevel(lv.id) }
                            .allowsHitTesting(!store.starting)
                    }

                    Text("the mossback bridge")
                        .font(Type.small).italic().foregroundStyle(Palette.nightSoft.opacity(0.55))
                        .position(x: w * 0.5, y: trailHeight - 46)
                }
                .frame(width: w, height: trailHeight)
            }
            .defaultScrollAnchor(.bottom)   // begin at the bridge; scroll UP to climb
        }
    }

    private func clampX(_ x: CGFloat, _ w: CGFloat) -> CGFloat { min(max(x, 72), w - 72) }

    private var sky: some View {
        LinearGradient(colors: [
            Color(hex: 0x070510),   // deep cosmic (top, the Oracle)
            Color(hex: 0x0D0A1A),
            Color(hex: 0x14111E),
            Color(hex: 0x1E1726),
            Palette.nightTop,       // warming toward earth
            Palette.nightBot,       // earthy (bottom, the bridge)
        ], startPoint: .top, endPoint: .bottom)
    }

    private func drawStars(_ ctx: GraphicsContext, _ size: CGSize) {
        for (sx, sy, r, op) in Self.stars {
            let rect = CGRect(x: sx * size.width - r, y: sy * size.height - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(op)))
        }
    }

    // a soft gold halo behind the Oracle at the apex
    private func drawGlow(_ ctx: GraphicsContext, _ size: CGSize) {
        let o = point(order.count - 1, size.width)
        let R: CGFloat = 120
        let rect = CGRect(x: o.x - R, y: o.y - R, width: R * 2, height: R * 2)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [Palette.gold.opacity(0.30), .clear]),
            center: o, startRadius: 4, endRadius: R))
    }

    private func drawTrail(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width
        guard order.count >= 2 else { return }
        for i in 0..<(order.count - 1) {
            let a = point(i, w), b = point(i + 1, w)
            var seg = Path()
            seg.move(to: a)
            seg.addCurve(to: b,
                         control1: CGPoint(x: a.x, y: (a.y + b.y) / 2),
                         control2: CGPoint(x: b.x, y: (a.y + b.y) / 2))
            if solved(order[i].id) {
                ctx.stroke(seg, with: .color(Palette.gold.opacity(0.18)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                ctx.stroke(seg, with: .color(Palette.gold.opacity(0.95)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            } else {
                ctx.stroke(seg, with: .color(Palette.nightSoft.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 11]))
            }
        }
    }
}

// One gate on the trail: a circular portrait with a state ring, a progress badge, the gatekeeper's
// name + difficulty keys beneath, and — for the next gate to play — a pulsing ring and a Begin/Continue pill.
private struct TrailNode: View {
    let level: LevelChoice
    var progress: LevelProgress?
    var isFrontier: Bool
    @State private var pulse = false

    private var solved: Bool { progress?.won == true }
    private var inProgress: Bool {
        guard let p = progress else { return false }
        return p.status == "active" && !p.won && p.turnsTaken >= 1
    }
    private var phaseColor: Color { Palette.phaseTint(Phase(rawValue: progress?.phase ?? "cold") ?? .cold) }
    private var ringColor: Color {
        solved ? Palette.gold : (inProgress ? phaseColor : Palette.nightSoft.opacity(0.55))
    }

    var body: some View {
        portrait
            .frame(width: 76, height: 76)
            .overlay(alignment: .top) { caption.frame(width: 140).offset(y: 88) }
            .onAppear {
                guard isFrontier else { return }
                withAnimation(.easeOut(duration: 1.7).repeatForever(autoreverses: false)) { pulse = true }
            }
    }

    private var portrait: some View {
        ZStack {
            if isFrontier {
                Circle().stroke(Palette.gold.opacity(0.7), lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulse ? 1.22 : 1.0)
                    .opacity(pulse ? 0 : 0.85)
            }
            Group {
                if UIImage(named: level.thumb) != nil {
                    Image(level.thumb).resizable().scaledToFill()
                } else {
                    ZStack {
                        Palette.troll
                        Text(String(level.gatekeeper.prefix(1)))
                            .font(Type.serif(26, .bold)).foregroundStyle(Palette.trollText)
                    }
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(Circle())
            .overlay(Circle().stroke(ringColor, lineWidth: solved || isFrontier ? 3 : 2))
            .shadow(color: .black.opacity(0.55), radius: 7, y: 3)
            .saturation(solved || inProgress || isFrontier ? 1 : 0.7)
            .opacity(solved || inProgress || isFrontier ? 1 : 0.92)
        }
        .frame(width: 76, height: 76)
        .overlay(alignment: .bottomTrailing) { badge.offset(x: 3, y: 3) }
    }

    @ViewBuilder private var badge: some View {
        if solved {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 17))
                .foregroundStyle(Palette.gold)
                .background(Circle().fill(Palette.nightBot).frame(width: 18, height: 18))
        } else if inProgress {
            Circle().fill(phaseColor)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Palette.nightBot, lineWidth: 2))
        }
    }

    private var caption: some View {
        VStack(spacing: 4) {
            Text(level.gatekeeper)
                .font(Type.label)
                .foregroundStyle(solved ? Palette.gold : Palette.nightText)
                .shadow(color: .black.opacity(0.7), radius: 4, y: 1)
            HStack(spacing: 3) {
                ForEach(0..<level.difficulty, id: \.self) { _ in
                    Image(systemName: "key.fill").font(.system(size: 7)).foregroundStyle(Palette.amber)
                }
            }
            if isFrontier {
                Text(inProgress ? "Continue" : "Begin")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.nightBot)
                    .padding(.horizontal, 9).padding(.vertical, 2)
                    .background(Capsule().fill(Palette.gold))
                    .padding(.top, 1)
            }
        }
        .multilineTextAlignment(.center)
    }
}
