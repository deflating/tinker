import SwiftUI

struct MemoryDetailView: View {
    @Bindable var vm: MemoryViewModel
    let path: String

    var body: some View {
        ScrollView {
            if vm.isLoading {
                ProgressView()
                    .padding(.top, 40)
            } else if let content = vm.selectedContent {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.warmText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView(
                    "File not available",
                    systemImage: "icloud.slash",
                    description: Text("Could not load from iCloud")
                )
            }
        }
        .background(Color.warmBg)
        .navigationTitle(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.capitalized)
        .task { await vm.loadFile(path: path) }
    }
}
