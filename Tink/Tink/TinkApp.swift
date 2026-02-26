import SwiftUI

@main
struct TinkApp: App {
    var body: some Scene {
        WindowGroup {
            HomeTabView()
                .preferredColorScheme(.dark)
                .tint(Color.accentTeal)
        }
    }
}

extension Color {
    static let accentTeal = Color(red: 0.2, green: 0.62, blue: 0.58)
    static let warmBg = Color(red: 0.08, green: 0.07, blue: 0.06)
    static let warmCard = Color(red: 0.14, green: 0.12, blue: 0.11)
    static let warmText = Color(red: 0.92, green: 0.88, blue: 0.82)
    static let warmSecondary = Color(red: 0.6, green: 0.55, blue: 0.48)
}
