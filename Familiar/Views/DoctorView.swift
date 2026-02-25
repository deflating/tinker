import SwiftUI

struct DoctorView: View {
    let workingDirectory: String
    @State private var doctor = DoctorService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "stethoscope")
                    .font(.title2)
                    .foregroundStyle(FamiliarApp.accent)
                Text("Diagnostics")
                    .font(.title2.bold())
                Spacer()
                Button(action: { doctor.runAll(workingDirectory: workingDirectory) }) {
                    Label(doctor.isRunning ? "Running…" : "Run Checks", systemImage: "arrow.clockwise")
                }
                .disabled(doctor.isRunning)
            }

            if doctor.checks.isEmpty {
                VStack(spacing: 8) {
                    Text("Run diagnostics to check your Claude Code environment.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(doctor.checks) { check in
                    HStack(alignment: .top, spacing: 10) {
                        statusIcon(check.status)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.name)
                                .font(.body.weight(.medium))
                            Text(check.description)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if !check.detail.isEmpty {
                                Text(check.detail)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(check.status == .failed ? .red : .secondary)
                                    .textSelection(.enabled)
                            }
                            if let fix = check.fix {
                                HStack(spacing: 4) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.orange)
                                    Text(fix)
                                        .font(.callout)
                                        .foregroundStyle(.orange)
                                        .textSelection(.enabled)
                                }
                                .padding(.top, 2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .padding(20)
        .onAppear {
            doctor.runAll(workingDirectory: workingDirectory)
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: DoctorService.Check.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
