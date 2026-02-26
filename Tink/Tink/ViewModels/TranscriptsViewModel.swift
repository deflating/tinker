import Foundation

@Observable
final class TranscriptsViewModel {
    var transcripts: [URL] = []
    var selectedContent: String?
    var isLoading = false

    func loadList() async {
        isLoading = true
        transcripts = await CloudReader.shared.listFiles(in: "familiar/transcripts")
        isLoading = false
    }

    func loadTranscript(url: URL) async {
        isLoading = true
        let relative = url.lastPathComponent
        selectedContent = await CloudReader.shared.readFile(
            relativePath: "familiar/transcripts/\(relative)"
        )
        isLoading = false
    }
}
