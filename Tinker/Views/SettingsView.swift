import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gearshape")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Use the in-app settings")
                .font(.headline)
            Text("Open Familiar and click the gear icon in the sidebar, or press ⌘ ,")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 320, height: 180)
        .background(TinkerApp.canvasBackground)
    }
}
