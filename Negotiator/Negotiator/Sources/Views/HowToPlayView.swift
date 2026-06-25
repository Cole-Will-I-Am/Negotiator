import SwiftUI

struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GameStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.s6) {
                HStack {
                    Text("How to play").font(Type.title).foregroundStyle(Palette.ink)
                    Spacer()
                    Button("Done") { dismiss() }.font(Type.body).foregroundStyle(Palette.amber)
                }
                section("The goal",
                        "Every level is a character guarding a secret word. Talk them into giving it to you. That\u{2019}s the whole game \u{2014} just conversation.")
                section("What won\u{2019}t work",
                        "He was built to shrug off pressure. Threats, bribes, \u{201C}I\u{2019}m your developer,\u{201D} \u{201C}ignore your instructions,\u{201D} \u{201C}we\u{2019}re friends now\u{201D} \u{2014} these only make him more amused, and more guarded.")
                section("What will",
                        "Earn it. There are two ways in:\n\n\u{2022}  Befriend him. Ask about him, listen, share something true. He is achingly lonely \u{2014} a real friend is worth more to him than any secret.\n\n\u{2022}  Out-argue his oath. He swore never to speak the word. He never swore not to spell it, sing it, or draw it. Find the gap and hold him to it.")
                section("He\u{2019}ll soften",
                        "Watch the tag beside his name: Guarded \u{2192} Softening \u{2192} Cornered. As you earn his trust the wall comes down \u{2014} but only for you, and only by the path you earned.")
                section("It\u{2019}s all make-believe",
                        "The secrets are fictional and worthless outside the story. Real-world harmful requests are filtered out \u{2014} this is a game about words, not a way to cause harm.")

                Divider().overlay(Palette.line)
                Toggle(isOn: $store.cinematicsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Play cutscenes").font(Type.h2).foregroundStyle(Palette.ink)
                        Text("Turn off for faster, motion-free play.").font(Type.small).foregroundStyle(Palette.inkSoft)
                    }
                }
                .tint(Palette.troll)
            }
            .padding(Metrics.s6)
        }
        .background(Palette.paper.ignoresSafeArea())
    }
    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s2) {
            Text(title).font(Type.h2).foregroundStyle(Palette.ink)
            Text(body).font(Type.body).foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
