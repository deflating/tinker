import Foundation

@Observable
final class MemoryViewModel {
    var files: [(name: String, path: String)] = [
        ("Semantic Memory", "memorable/semantic.md"),
        ("Episodic Memory", "memorable/episodic.md"),
        ("Working Memory", "memorable/working.md"),
    ]
    var selectedContent: String?
    var isLoading = false

    func loadFile(path: String) async {
        isLoading = true
        selectedContent = await CloudReader.shared.readFile(relativePath: path)
        isLoading = false
    }
}
