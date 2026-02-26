import SwiftUI

struct SessionListView: View {
    var connection: TinkerConnection
    @State private var selectedSession: Session?
    @State private var searchText = ""

    var body: some View {
        Group {
            if connection.isConnected {
                VStack(spacing: 0) {
                    sessionList
                    bottomBar
                }
            } else {
                connectingState
            }
        }
        .navigationTitle(connection.connectedHost?.name ?? "Sessions")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedSession) { _ in
            ChatView(connection: connection)
        }
    }

    private var connectingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch connection.state {
        case .connecting: "Connecting..."
        case .authenticating: "Authenticating..."
        case .error(let msg): msg
        default: "Connecting..."
        }
    }

    private var sessionList: some View {
        List {
            if !pinnedSessions.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedSessions) { session in
                        sessionRow(session)
                    }
                }
            }
            Section("Sessions") {
                ForEach(unpinnedSessions) { session in
                    sessionRow(session)
                }
            }
        }
        .listStyle(.plain)
    }

    private func sessionRow(_ session: Session) -> some View {
        Button {
            connection.switchSession(session.id)
            selectedSession = session
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.body)
                    .lineLimit(1)
                if !session.lastMessage.isEmpty {
                    Text(session.lastMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .tint(.primary)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            Button {
                connection.createNewSession()
                selectedSession = connection.sessions.first
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.title3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var filteredSessions: [Session] {
        guard !searchText.isEmpty else { return connection.sessions }
        let query = searchText.lowercased()
        return connection.sessions.filter {
            $0.name.lowercased().contains(query) || $0.lastMessage.lowercased().contains(query)
        }
    }

    private var pinnedSessions: [Session] {
        filteredSessions.filter(\.isPinned).sorted { $0.updatedAt > $1.updatedAt }
    }

    private var unpinnedSessions: [Session] {
        filteredSessions.filter { !$0.isPinned }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
