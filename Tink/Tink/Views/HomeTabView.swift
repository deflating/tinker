import SwiftUI

struct HomeTabView: View {
    var body: some View {
        TabView {
            Tab("Memory", systemImage: "brain.head.profile") {
                MemoryListView()
            }
            Tab("Seeds", systemImage: "leaf") {
                SeedListView()
            }
            Tab("Transcripts", systemImage: "text.bubble") {
                TranscriptListView()
            }
            Tab("Signal", systemImage: "paperplane") {
                QuickMessageView()
            }
        }
    }
}
