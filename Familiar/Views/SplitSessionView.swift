import SwiftUI

/// A read-only view of a session's messages for split-view comparison
struct SplitSessionView: View {
    let session: Session
    let messages: [ChatMessage]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 11))
                    .foregroundStyle(TinkerApp.accent)
                Text(session.name)
                    .font(.callout.bold())
                    .lineLimit(1)
                Spacer()
                Text("\(messages.count) messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(TinkerApp.surfaceBackground)

            Divider()

            if messages.isEmpty {
                Spacer()
                Text("Empty session")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(TinkerApp.canvasBackground)
    }
}
