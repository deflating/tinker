import SwiftUI

@main
struct TinkApp: App {
    @State private var connection = TinkerConnection()
    @AppStorage("appearance") private var appearance: AppAppearance = .dark

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView(connection: connection)
            }
            .preferredColorScheme(appearance.colorScheme)
        }
    }
}
