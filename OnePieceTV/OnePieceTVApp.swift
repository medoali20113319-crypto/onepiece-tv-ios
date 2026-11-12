// OnePieceTVApp.swift — app entry. Shows the login screen until an
// account is selected, then the home screen. Arabic is the default
// language; the layout flips RTL automatically from the locale.

import SwiftUI

@main
struct OnePieceTVApp: App {
    @StateObject private var store = AppStore.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if store.currentAccount == nil {
                    LoginView()
                } else {
                    HomeView()
                }
            }
            .environmentObject(store)
            .environment(\.layoutDirection,
                         store.language == .arabic ? .rightToLeft : .leftToRight)
            .preferredColorScheme(.dark)
            .onAppear {
                // RTL note: SwiftUI flips automatically with the layout
                // direction above; the Android app forces RTL the same way.
            }
        }
    }
}
