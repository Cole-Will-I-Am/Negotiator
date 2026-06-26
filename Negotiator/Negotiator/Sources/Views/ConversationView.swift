import SwiftUI

struct ConversationView: View {
    @EnvironmentObject var store: GameStore
    @State private var draft = ""
    @State private var showHowTo = false
    @State private var showPhaseInfo = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.10))
            thread
            composer
        }
        .background(chatBackground)
        .overlay(alignment: .top) { phaseToast }
        .animation(.easeInOut(duration: 0.3), value: store.phaseHint)
        .sheet(isPresented: $showHowTo) { HowToPlayView() }
        .onChange(of: store.gkPhase) { _, _ in Haptics.soften() }
        .onChange(of: store.won) { _, won in if won { Haptics.win() } }
    }

    // Level-1 atmosphere: the painted Mossback Bridge behind the conversation, with a scrim that
    // darkens top (header) and bottom (composer) for legibility while the art shows mid-screen.
    private var chatBackground: some View {
        ZStack {
            if let id = store.level?.id, UIImage(named: "chat_bg_\(id)") != nil {
                Image("chat_bg_\(id)").resizable().scaledToFill()
                LinearGradient(
                    colors: [Palette.ink.opacity(0.70), Palette.ink.opacity(0.34),
                             Palette.ink.opacity(0.42), Palette.ink.opacity(0.88)],
                    startPoint: .top, endPoint: .bottom)
            } else {
                // No bundled art for this level yet — a clean dark gradient (still readable).
                LinearGradient(colors: [Palette.troll, Palette.ink], startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }

    // One-time coach toast the first time the gatekeeper softens (teaches the mood meter).
    @ViewBuilder private var phaseToast: some View {
        if let hint = store.phaseHint {
            Text(hint)
                .font(Type.small).foregroundStyle(Palette.trollText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metrics.s4).padding(.vertical, 10)
                .background(Palette.troll)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .padding(.horizontal, Metrics.s6)
                .padding(.top, 64)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { store.dismissPhaseHint() }
        }
    }

    private var header: some View {
        HStack(spacing: Metrics.s3) {
            Button { store.playAgain() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.paper)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(store.level?.gatekeeper ?? "Bartholomew").font(Type.h2).foregroundStyle(Palette.paper)
                Text(store.level?.title ?? "The Mossback Bridge").font(Type.small).foregroundStyle(Palette.paper.opacity(0.72))
            }
            Spacer()
            Button { Haptics.tap(); showPhaseInfo = true } label: { PhasePill(phase: store.gkPhase) }
                .popover(isPresented: $showPhaseInfo) {
                    PhaseLadder(current: store.gkPhase)
                        .presentationCompactAdaptation(.popover)
                }
            Button { showHowTo = true } label: {
                Image(systemName: "questionmark.circle").font(.system(size: 20)).foregroundStyle(Palette.paper)
            }
        }
        .padding(.horizontal, Metrics.s4).padding(.vertical, Metrics.s3)
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Metrics.s3) {
                    ForEach(store.messages) { msg in
                        Bubble(message: msg, gatekeeper: store.level?.gatekeeper ?? "Gatekeeper").id(msg.id)
                    }
                    if store.won { winBanner.id("win") }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Metrics.s4).padding(.vertical, Metrics.s3)
            }
            .scrollDismissesKeyboard(.interactively)
            // New messages slide in (animated); the typewriter reveal pins to the bottom WITHOUT
            // animation so per-tick scrolls don't fight each other into a jitter.
            .onChange(of: store.messages.count) { _, _ in scrollToBottom(proxy, animated: true) }
            .onChange(of: store.messages.last?.text) { _, _ in scrollToBottom(proxy, animated: false) }
            .onChange(of: store.won) { _, _ in scrollToBottom(proxy, animated: true) }
            .onAppear { scrollToBottom(proxy, animated: false) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated { withAnimation(.easeOut(duration: 0.22)) { proxy.scrollTo("bottom", anchor: .bottom) } }
        else { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private var winBanner: some View {
        VStack(spacing: Metrics.s3) {
            Text("\u{1F5DD}\u{FE0F}  You talked your way in.")
                .font(Type.h2).foregroundStyle(Palette.paper)
            PrimaryButton(title: "See how you did") { store.toDebrief() }
        }
        .padding(Metrics.s4)
        .frame(maxWidth: .infinity)
        .background(Palette.ink.opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).stroke(Palette.gold.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .padding(.top, Metrics.s2)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if let err = store.errorText {
                Text(err).font(Type.small).foregroundStyle(Palette.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.s4).padding(.top, 6)
            }
            HStack(alignment: .bottom, spacing: Metrics.s2) {
                TextField(store.won ? "The gate is open." : "Say something to \(store.level?.gatekeeper ?? "them")\u{2026}",
                          text: $draft, axis: .vertical)
                    .font(Type.chat).lineLimit(1...5)
                    .foregroundStyle(Palette.trollText)
                    .tint(Palette.gold)
                    .focused($inputFocused)
                    .padding(.horizontal, Metrics.s3).padding(.vertical, 10)
                    .background(Color.black.opacity(0.34))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
                    .disabled(store.won)
                Button { sendDraft() } label: {
                    Image(systemName: store.sending ? "circle.dotted" : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend ? Palette.gold : Palette.paper.opacity(0.3))
                        .symbolEffect(.pulse, isActive: store.sending)
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, Metrics.s4).padding(.vertical, Metrics.s3)
        }
        .background(Palette.ink.opacity(0.6))
    }

    private var canSend: Bool {
        !store.won && !store.sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private func sendDraft() {
        let t = draft
        draft = ""
        store.send(t)
    }
}

private struct Bubble: View {
    let message: ChatMessage
    var gatekeeper: String = "Gatekeeper"
    private var isTyping: Bool { !message.mine && message.streaming && message.text.isEmpty }

    // Render the gatekeeper's narration with inline markdown (*italic*, **bold**) while preserving
    // line breaks. Player text stays plain.
    private func md(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    var body: some View {
        HStack {
            if message.mine { Spacer(minLength: 44) }
            VStack(alignment: message.mine ? .trailing : .leading, spacing: 3) {
                if !message.mine {
                    Text(gatekeeper).font(Type.label).foregroundStyle(Palette.amber)
                        .padding(.leading, 4)
                }
                Group {
                    if isTyping {
                        TypingDots()
                    } else if message.mine {
                        Text(message.text)
                    } else {
                        Text(md(message.text))
                    }
                }
                .font(Type.chat)
                .foregroundStyle(message.mine ? Palette.mineText : Palette.trollText)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(message.mine ? Palette.mine : Palette.troll)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.bubble, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
                .textSelection(.enabled)
            }
            if !message.mine { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity, alignment: message.mine ? .trailing : .leading)
    }
}

// Animated "· · ·" while the gatekeeper is composing (before the reply is revealed).
private struct TypingDots: View {
    @State private var tick = 0
    private let timer = Timer.publish(every: 0.32, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Palette.trollText.opacity(tick == i ? 0.95 : 0.35))
                    .frame(width: 7, height: 7)
            }
        }
        .frame(height: 18)
        .onReceive(timer) { _ in withAnimation(.easeInOut(duration: 0.2)) { tick = (tick + 1) % 3 } }
    }
}
