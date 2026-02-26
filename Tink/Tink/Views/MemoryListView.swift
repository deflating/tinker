import SwiftUI

struct MemoryListView: View {
    @State private var vm = MemoryViewModel()

    var body: some View {
        NavigationStack {
            List(vm.files, id: \.path) { file in
                NavigationLink(file.name, value: file.path)
            }
            .navigationTitle("Memory")
            .navigationDestination(for: String.self) { path in
                MemoryDetailView(vm: vm, path: path)
            }
            .listStyle(.insetGrouped)
        }
    }
}
