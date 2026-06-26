import SwiftUI

// Cinemagraph intro: the painted Mossback Bridge still, with Bartholomew's amber eyes blinking
// (a fast crossfade between the open frame and an "eyes-closed" frame), a slow push-in, and the
// title fading up. Robust across screen sizes — both frames are the same image displayed
// identically, so the blink is a whole-frame crossfade with no per-eye coordinate anchoring.
struct IntroCutscene: View {
    @State private var closed = false
    @State private var zoom = false
    @State private var showTitle = false
    @State private var blinkTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black
            GeometryReader { geo in
                Image("intro_bridge")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay(
                        Image("intro_bridge_closed")
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
                Text("The Mossback Bridge")
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
            blinkTask = makeBlinkTask()
        }
        .onDisappear { blinkTask?.cancel() }
    }

    private func makeBlinkTask() -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            while !Task.isCancelled {
                await blink()
                if Bool.random() {                              // occasional natural double-blink
                    try? await Task.sleep(for: .milliseconds(170))
                    await blink()
                }
                try? await Task.sleep(for: .seconds(Double.random(in: 2.4...4.0)))
            }
        }
    }
    private func blink() async {
        withAnimation(.easeIn(duration: 0.09)) { closed = true }
        try? await Task.sleep(for: .milliseconds(95))
        withAnimation(.easeOut(duration: 0.14)) { closed = false }
        try? await Task.sleep(for: .milliseconds(140))
    }
}
