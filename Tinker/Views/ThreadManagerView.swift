import SwiftUI

struct ThreadManagerView: View {
    @Bindable var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newThreadName = ""
    @State private var newThreadColor = "blue"
    @State private var editingThreadId: String?
    @State private var editingName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Threads")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // New thread input
            HStack(spacing: 8) {
                Menu {
                    ForEach(SessionThread.threadColors, id: \.self) { color in
                        Button {
                            newThreadColor = color
                        } label: {
                            HStack {
                                Circle()
                                    .fill(threadColor(color))
                                    .frame(width: 10, height: 10)
                                Text(color.capitalized)
                                if newThreadColor == color {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Circle()
                        .fill(threadColor(newThreadColor))
                        .frame(width: 12, height: 12)
                        .padding(6)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                TextField("New thread name", text: $newThreadName)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onSubmit { createThread() }

                Button("Add", action: createThread)
                    .disabled(newThreadName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Divider()

            // Thread list
            if viewModel.threads.isEmpty {
                VStack(spacing: 8) {
                    Text("No threads yet")
                        .foregroundStyle(.secondary)
                    Text("Threads group related sessions together.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.threads) { thread in
                        threadRow(thread)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func threadRow(_ thread: SessionThread) -> some View {
        let sessionCount = viewModel.sessions.filter { $0.threadId == thread.id }.count

        return HStack(spacing: 8) {
            Menu {
                ForEach(SessionThread.threadColors, id: \.self) { color in
                    Button {
                        viewModel.updateThreadColor(thread, to: color)
                    } label: {
                        HStack {
                            Circle()
                                .fill(threadColor(color))
                                .frame(width: 10, height: 10)
                            Text(color.capitalized)
                            if thread.color == color {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Circle()
                    .fill(threadColor(thread.color))
                    .frame(width: 10, height: 10)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if editingThreadId == thread.id {
                TextField("Thread name", text: $editingName)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { viewModel.renameThread(thread, to: trimmed) }
                        editingThreadId = nil
                    }
                    .onExitCommand { editingThreadId = nil }
            } else {
                Text(thread.name)
                    .font(.body)
            }

            Spacer()

            Text("\(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button {
                editingName = thread.name
                editingThreadId = thread.id
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                viewModel.deleteThread(thread)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func createThread() {
        let trimmed = newThreadName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        _ = viewModel.createThread(name: trimmed, color: newThreadColor)
        newThreadName = ""
    }
}
