import SwiftUI

@main
struct NegotiatorApp: App {
    @StateObject private var store = GameStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { store.bootstrap() }
                .preferredColorScheme(.light)
        }
    }
}
