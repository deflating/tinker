import SwiftUI

// MARK: - Spotlight-Style Quick Prompt

struct SpotlightOverlay: View {
    @Binding var isPresented: Bool
    let onSubmit: (String) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "sparkle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(FamiliarApp.accent)

                TextField("Ask Familiar anything…", text: $text)
                    .font(.system(size: 20, weight: .light))
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSubmit(trimmed)
                        text = ""
                        isPresented = false
                    }
                    .onExitCommand {
                        text = ""
                        isPresented = false
                    }

                if !text.isEmpty {
                    Text("⏎")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
            }
            .frame(maxWidth: 560)
            .padding(.top, 100)

            Spacer()
        }
        .onAppear { isFocused = true }
    }
}
