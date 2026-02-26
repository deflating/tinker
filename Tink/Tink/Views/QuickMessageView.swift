import SwiftUI

struct QuickMessageView: View {
    @State private var vm = QuickMessageViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Message", text: $vm.message, axis: .vertical)
                    .lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                Button {
                    Task { await vm.send() }
                } label: {
                    HStack {
                        if vm.status == .sending {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(vm.status == .sending ? "Sending..." : "Send")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.message.trimmingCharacters(in: .whitespaces).isEmpty || vm.status == .sending)
                .padding(.horizontal)

                switch vm.status {
                case .sent:
                    Label("Sent", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.opacity)
                case .error(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal)
                default:
                    EmptyView()
                }

                if !vm.history.isEmpty {
                    List {
                        Section("Recent") {
                            ForEach(vm.history, id: \.self) { msg in
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(Color.warmSecondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Signal")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
    }
}
