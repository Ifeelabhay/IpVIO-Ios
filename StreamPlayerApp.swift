import SwiftUI

@main
struct StreamPlayerApp: App {
    @StateObject private var store = PlaylistStore()
    @StateObject private var library = Library()
    @StateObject private var history = History()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(library)
                .environmentObject(history)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
