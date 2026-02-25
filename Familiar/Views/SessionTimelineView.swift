import SwiftUI

struct SessionTimelineView: View {
    let sessions: [Session]
    let onSelect: (Session) -> Void

    @Environment(\.dismiss) private var dismiss

    private var groupedByDay: [(String, [Session])] {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"

        var groups: [(String, [Session])] = []
        var currentKey = ""
        var currentBucket: [Session] = []

        let sorted = sessions.sorted { $0.updatedAt > $1.updatedAt }
        for session in sorted {
            let key = formatter.string(from: session.updatedAt)
            if key != currentKey {
                if !currentBucket.isEmpty {
                    groups.append((currentKey, currentBucket))
                }
                currentKey = key
                currentBucket = [session]
            } else {
                currentBucket.append(session)
            }
        }
        if !currentBucket.isEmpty {
            groups.append((currentKey, currentBucket))
        }
        return groups
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Session Timeline")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groupedByDay, id: \.0) { dayLabel, daySessions in
                        // Day header
                        Text(dayLabel)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        ForEach(daySessions) { session in
                            TimelineRow(session: session, onSelect: {
                                onSelect(session)
                                dismiss()
                            })
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(FamiliarApp.canvasBackground)
    }
}

private struct TimelineRow: View {
    let session: Session
    let onSelect: () -> Void
    @State private var isHovered = false

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: session.updatedAt)
    }

    private var directoryName: String {
        if let dir = session.workingDirectory {
            return (dir as NSString).lastPathComponent
        }
        return ""
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                // Timeline track
                VStack(spacing: 0) {
                    Circle()
                        .fill(FamiliarApp.accent)
                        .frame(width: 10, height: 10)
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 2)
                }
                .frame(width: 10)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text(timeString)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if !session.lastMessage.isEmpty {
                        Text(session.lastMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if !directoryName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                            Text(directoryName)
                                .font(.caption)
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.trailing, 12)
            }
            .padding(.horizontal, 24)
            .background(isHovered ? Color.primary.opacity(0.04) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
