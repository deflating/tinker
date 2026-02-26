import SwiftUI

struct HomeView: View {
    var connection: TinkerConnection
    @State private var selectedHost: DiscoveredHost?
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if connection.discoveredHosts.isEmpty {
                searchingState
            } else {
                hostGrid
            }

            Spacer()

            bottomBar
        }
        .navigationTitle("Tink")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedHost) { host in
            SessionListView(connection: connection)
                .onAppear { connection.connect(to: host) }
                .onDisappear {
                    if !connection.isConnected {
                        connection.disconnect()
                    }
                }
        }
        .onAppear {
            connection.startSearching()
        }
        .onDisappear {
            connection.stopSearching()
        }
    }

    // MARK: - Searching

    private var searchingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Looking for Tinker on your network...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Host Grid

    private var hostGrid: some View {
        VStack(spacing: 24) {
            ForEach(connection.discoveredHosts) { host in
                Button {
                    selectedHost = host
                } label: {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: 80, height: 80)
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 32))
                                .foregroundStyle(.primary)
                        }
                        Text(host.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            Spacer()
        }
        .padding()
    }
}
