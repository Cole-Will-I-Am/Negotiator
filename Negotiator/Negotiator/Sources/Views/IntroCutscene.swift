import SwiftUI

// Cinemagraph intro: the painted Mossback Bridge still, with Bartholomew's amber eyes blinking
// (a fast crossfade between the open frame and an "eyes-closed" frame), a slow push-in, and the
// title fading up. Robust across screen sizes — both frames are the same image displayed
// identically, so the blink is a whole-frame crossfade with no per-eye coordinate anchoring.
struct IntroCutscene: View {
    let art: IntroArt
    @State private var closed = false
    @State private var zoom = false
    @State private var showTitle = false
    @State private var blinkTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black
            GeometryReader { geo in
                Image(art.open)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay(
                        Image(art.closed)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .opacity(closed ? 1 : 0)
                    )
                    .scaleEffect(zoom ? 1.07 : 1.0)
                    .clipped()
            }
            VStack {
                Spacer()
                Text(art.title)
                    .font(Type.serif(28, .bold))
                    .foregroundStyle(Palette.paper)
                    .shadow(color: .black.opacity(0.85), radius: 6, y: 2)
                    .opacity(showTitle ? 1 : 0)
                    .padding(.bottom, 90)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8.5)) { zoom = true }
            withAnimation(.easeIn(duration: 1.2).delay(4.8)) { showTitle = true }
            blinkTask = makeAnimTask()
        }
        .onDisappear { blinkTask?.cancel() }
    }

    private func makeAnimTask() -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            while !Task.isCancelled {
                if art.anim == "flicker" {
                    await flickerBurst()
                    try? await Task.sleep(for: .seconds(Double.random(in: 1.6...3.8)))
                } else if art.anim == "pulse" {
                    await pulse()           // continuous; the scale-light breathes, no gap between beats
                } else {
                    await blink()
                    if Bool.random() {                              // occasional natural double-blink
                        try? await Task.sleep(for: .milliseconds(170))
                        await blink()
                    }
                    try? await Task.sleep(for: .seconds(Double.random(in: 2.4...4.0)))
                }
            }
        }
    }
    private func blink() async {
        withAnimation(.easeIn(duration: 0.09)) { closed = true }
        try? await Task.sleep(for: .milliseconds(95))
        withAnimation(.easeOut(duration: 0.14)) { closed = false }
        try? await Task.sleep(for: .milliseconds(140))
    }
    // The scales of justice: a slow, solemn breathing of the scale-light — a long ease in to the
    // dimmed frame and back, like a steady heartbeat. Never fully dark (the dim frame only halves
    // the glow), so it reads as breathing, not blinking.
    private func pulse() async {
        withAnimation(.easeInOut(duration: 1.9)) { closed = true }
        try? await Task.sleep(for: .milliseconds(1900))
        withAnimation(.easeInOut(duration: 2.2)) { closed = false }
        try? await Task.sleep(for: .milliseconds(2200))
    }
    // A guttering lamp: a quick irregular burst of on/off, sometimes a longer near-death dim.
    private func flickerBurst() async {
        let n = Int.random(in: 2...6)
        for _ in 0..<n {
            withAnimation(.linear(duration: 0.04)) { closed = true }
            try? await Task.sleep(for: .milliseconds(Int.random(in: 35...110)))
            withAnimation(.linear(duration: 0.04)) { closed = false }
            try? await Task.sleep(for: .milliseconds(Int.random(in: 30...95)))
        }
        if Bool.random() {
            withAnimation(.easeOut(duration: 0.12)) { closed = true }
            try? await Task.sleep(for: .milliseconds(Int.random(in: 180...430)))
            withAnimation(.easeIn(duration: 0.20)) { closed = false }
        }
    }
}
