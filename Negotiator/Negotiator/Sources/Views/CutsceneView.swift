import SwiftUI
import AVKit
import AVFoundation

// Full-screen cutscene host. Resolution order: real bundled mp4 -> procedural intro scene ->
// (win) a gold bloom. Always skippable, reduce-motion-aware, and hard-timeout-guarded so a
// missing/stuck clip can never trap the player. Calls store.cutsceneFinished() exactly once.
struct CutsceneView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSkip = false
    @State private var finished = false

    private var cutscene: Cutscene { store.activeCutscene ?? .intro }
    private var videoURL: URL? { Bundle.main.url(forResource: cutscene.videoName, withExtension: "mp4") }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            VStack {
                HStack {
                    Spacer()
                    if showSkip {
                        Text("Skip")
                            .font(Type.label)
                            .foregroundStyle(Palette.trollText)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Capsule())
                            .transition(.opacity)
                    }
                }
                Spacer()
            }
            .padding(Metrics.s4)
        }
        .contentShape(Rectangle())
        .onTapGesture { if showSkip { finish() } }
        .onAppear {
            configureAudio()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation { showSkip = true } }
        }
    }

    @ViewBuilder private var content: some View {
        if reduceMotion {
            StaticPoster(cutscene: cutscene).onAppear { finishAfter(1.2) }
        } else if let url = videoURL {
            VideoPlayerHost(url: url, onEnd: finish).ignoresSafeArea()
                .onAppear { finishAfter(14) }            // safety cap (real clips ~5-9s)
        } else if cutscene == .intro {
            ProceduralCutscene(onEnd: finish).ignoresSafeArea()
                .onAppear { finishAfter(10.5) }          // safety > the scene's 8.5s self-end
        } else {
            GoldBloom().onAppear { finishAfter(1.5) }     // win, no asset
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        store.cutsceneFinished()
    }
    private func finishAfter(_ seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { finish() }
    }
    private func configureAudio() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

private struct VideoPlayerHost: UIViewControllerRepresentable {
    let url: URL
    let onEnd: () -> Void
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspectFill
        vc.view.backgroundColor = .black
        context.coordinator.observe(player: player, onEnd: onEnd)
        player.play()
        return vc
    }
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        private var token: NSObjectProtocol?
        func observe(player: AVPlayer, onEnd: @escaping () -> Void) {
            token = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
            ) { _ in onEnd() }
        }
        deinit { if let token { NotificationCenter.default.removeObserver(token) } }
    }
}

private struct StaticPoster: View {
    let cutscene: Cutscene
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.troll, Palette.ink], startPoint: .top, endPoint: .bottom)
            if cutscene == .intro {
                VStack(spacing: 14) {
                    Circle().fill(Palette.gold.opacity(0.9)).frame(width: 60, height: 60)
                    Text("The Mossback Bridge").font(Type.serif(26, .bold)).foregroundStyle(Palette.paper)
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct GoldBloom: View {
    @State private var on = false
    var body: some View {
        RadialGradient(colors: [Palette.mine, Palette.gold, Palette.ink],
                       center: .center,
                       startRadius: on ? 180 : 10,
                       endRadius: on ? 950 : 320)
            .ignoresSafeArea()
            .onAppear { withAnimation(.easeIn(duration: 1.3)) { on = true } }
    }
}
