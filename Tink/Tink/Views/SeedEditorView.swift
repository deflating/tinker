import SwiftUI

struct SeedEditorView: View {
    @Bindable var vm: SeedsViewModel
    let path: String

    var body: some View {
        VStack(spacing: 0) {
            if vm.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                TextEditor(text: $vm.editingContent)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Color.warmText)
                    .padding(8)
                    .background(Color.warmBg)
                    .onChange(of: vm.editingContent) { vm.autoSave() }
            }
        }
        .background(Color.warmBg)
        .navigationTitle(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.capitalized)
        .toolbar {
            if vm.isSaving {
                ToolbarItem(placement: .topBarTrailing) {
                    Label("Saving", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(Color.warmSecondary)
                }
            }
        }
        .task { await vm.loadFile(path: path) }
    }
}
