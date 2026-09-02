import SwiftUI

@main
struct PlyphApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { state.reload() }
                }
        }
    }
}
