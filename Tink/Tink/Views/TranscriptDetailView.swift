import SwiftUI

struct TranscriptDetailView: View {
    @Bindable var vm: TranscriptsViewModel
    let url: URL

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
                    "Could not load transcript",
                    systemImage: "icloud.slash"
                )
            }
        }
        .background(Color.warmBg)
        .navigationTitle(url.deletingPathExtension().lastPathComponent)
        .task { await vm.loadTranscript(url: url) }
    }
}
