import SwiftUI
import Network

struct HomeView: View {
    var connection: TinkerConnection
    @State private var selectedHost: DiscoveredHost?
    @State private var showSettings = false
    @State private var showManualConnect = false
    @State private var showScanner = false
    @State private var manualHost = ""
    @State private var manualPort = "8385"
    @State private var manualName = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Saved hosts
                    if !connection.savedHosts.isEmpty {
                        section("Hosts") {
                            ForEach(connection.savedHosts) { saved in
                                savedHostRow(saved)
                            }
                        }
                    }

                    // Add host
                    section(connection.savedHosts.isEmpty ? "Get Started" : "Add") {
                        Button {
                            showScanner = true
                        } label: {
                            hostRow(name: "Scan QR Code", icon: "qrcode.viewfinder", subtitle: "Pair with Tinker on your Mac")
                        }
                        Divider().padding(.horizontal, 16)
                        Button {
                            showManualConnect = true
                        } label: {
                            hostRow(name: "Enter Manually", icon: "keyboard", subtitle: "Connect by IP address")
                        }
                    }
                }
                .padding(20)
            }

            bottomBar
        }
        .navigationTitle("Tink")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedHost) { _ in
            SessionListView(connection: connection)
                .onDisappear {
                    if !connection.isConnected {
                        connection.disconnect()
                    }
                }
        }
        .sheet(isPresented: $showScanner) {
            QRScannerView(connection: connection)
        }
        .sheet(isPresented: $showManualConnect) {
            manualConnectSheet
        }
    }

    // MARK: - Section Builder

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(spacing: 2) {
                content()
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Row Builders

    @ViewBuilder
    private func hostRow(name: String, icon: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func savedHostRow(_ saved: SavedHost) -> some View {
        Button {
            connection.connect(host: saved.host, port: saved.port, name: saved.name)
            selectedHost = DiscoveredHost(
                id: saved.id,
                name: saved.name,
                endpoint: .hostPort(host: .init(saved.host), port: .init(rawValue: saved.port)!)
            )
        } label: {
            hostRow(name: saved.name, icon: "bolt.horizontal", subtitle: saved.host)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                connection.removeSavedHost(saved)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Manual Connect Sheet

    private var manualConnectSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("IP Address", text: $manualHost)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Port", text: $manualPort)
                        .keyboardType(.numberPad)
                    TextField("Name (optional)", text: $manualName)
                        .autocorrectionDisabled()
                }

                Section {
                    Button("Connect & Save") {
                        let port = UInt16(manualPort) ?? 8385
                        let name = manualName.isEmpty ? manualHost : manualName

                        let saved = SavedHost(name: name, host: manualHost, port: port)
                        connection.saveHost(saved)

                        connection.connect(host: manualHost, port: port, name: name)
                        selectedHost = DiscoveredHost(
                            id: saved.id,
                            name: name,
                            endpoint: .hostPort(host: .init(manualHost), port: .init(rawValue: port)!)
                        )

                        showManualConnect = false
                        manualHost = ""
                        manualPort = "8385"
                        manualName = ""
                    }
                    .disabled(manualHost.isEmpty)
                }
            }
            .navigationTitle("Add Host")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showManualConnect = false }
                }
            }
        }
        .presentationDetents([.medium])
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
