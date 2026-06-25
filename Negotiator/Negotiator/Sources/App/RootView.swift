import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            switch store.screen {
            case .loading:      LoadingView()
            case .onboarding:   OnboardingView()
            case .home:         HomeView()
            case .conversation: ConversationView()
            case .debrief:      DebriefView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.screen)
    }
}
