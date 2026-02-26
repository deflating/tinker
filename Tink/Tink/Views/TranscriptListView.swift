import SwiftUI

struct TranscriptListView: View {
    @State private var vm = TranscriptsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.transcripts.isEmpty {
                    ProgressView()
                } else if vm.transcripts.isEmpty {
                    ContentUnavailableView(
                        "No Transcripts",
                        systemImage: "text.bubble",
                        description: Text("Transcripts will appear here from iCloud")
                    )
                } else {
                    List(vm.transcripts, id: \.absoluteString) { url in
                        NavigationLink(url.deletingPathExtension().lastPathComponent, value: url)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Transcripts")
            .navigationDestination(for: URL.self) { url in
                TranscriptDetailView(vm: vm, url: url)
            }
            .task { await vm.loadList() }
            .refreshable { await vm.loadList() }
        }
    }
}
