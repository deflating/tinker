import SwiftUI

struct AddOnsSettingsView: View {
    @State private var configuringAddOn: String?

    var body: some View {
        if let configuringAddOn {
            // Show the config view for the selected add-on
            switch configuringAddOn {
            case "familiar":
                FamiliarConfigView(onBack: { self.configuringAddOn = nil })
            case "memorable":
                MemorableConfigView(onBack: { self.configuringAddOn = nil })
            default:
                Text("Unknown add-on")
            }
        } else {
            addOnsList
        }
    }

    private var addOnsList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(AddOnRegistry.all, id: \.id) { addOn in
                addOnRow(addOn)
            }
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private func addOnRow(_ addOn: any TinkerAddOn) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: addOn.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(addOn.name)
                        .font(.body.weight(.semibold))
                    Text(addOn.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { addOn.isEnabled },
                    set: { newValue in
                        // Need mutable copy via the concrete type
                        if let familiar = addOn as? FamiliarAddOn {
                            familiar.isEnabled = newValue
                        } else if let memorable = addOn as? MemorableAddOn {
                            memorable.isEnabled = newValue
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()

                Button("Configure") {
                    configuringAddOn = addOn.id
                }
                .controlSize(.small)
            }
            .padding(4)
        }
    }
}
