import SwiftUI

struct SettingsView: View {
    @AppStorage("signalEndpoint") private var endpoint = "http://192.168.68.58:8080/send"

    var body: some View {
        Form {
            Section("Signal Bridge") {
                TextField("Endpoint URL", text: $endpoint)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Section {
                LabeledContent("iCloud Container", value: "iCloud.app.familiar")
                LabeledContent("Bundle ID", value: "app.familiar.tink")
                LabeledContent("Version", value: "1.0")
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
    }
}
