import Foundation

@Observable
final class SeedsViewModel {
    var files: [(name: String, path: String)] = [
        ("Persona", "familiar/seeds/persona.md"),
        ("Preferences", "familiar/seeds/preferences.md"),
    ]
    var editingContent: String = ""
    var currentPath: String?
    var isLoading = false
    var isSaving = false

    private var saveTask: Task<Void, Never>?

    func loadFile(path: String) async {
        isLoading = true
        currentPath = path
        editingContent = await CloudReader.shared.readFile(relativePath: path) ?? ""
        isLoading = false
    }

    func autoSave() {
        guard let path = currentPath else { return }
        let content = editingContent
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            isSaving = true
            await CloudReader.shared.writeFile(relativePath: path, content: content)
            isSaving = false
        }
    }
}
