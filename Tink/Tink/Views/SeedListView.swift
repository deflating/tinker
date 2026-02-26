import SwiftUI

struct SeedListView: View {
    @State private var vm = SeedsViewModel()

    var body: some View {
        NavigationStack {
            List(vm.files, id: \.path) { file in
                NavigationLink(file.name, value: file.path)
            }
            .navigationTitle("Seeds")
            .navigationDestination(for: String.self) { path in
                SeedEditorView(vm: vm, path: path)
            }
            .listStyle(.insetGrouped)
        }
    }
}
