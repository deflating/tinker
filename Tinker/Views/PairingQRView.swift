import SwiftUI
import CoreImage.CIFilterBuiltins

struct PairingQRView: View {
    @State private var tailscaleIP: String = ""
    private let port: UInt16 = 8385
    private let token = KeychainSync.shared.token()
    private let machineName = Host.current().localizedName ?? "Tinker"

    var body: some View {
        VStack(spacing: 16) {
            Text("Pair with Tink")
                .font(.headline)

            if let image = qrImage {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Tailscale not available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 200, height: 200)
            }

            Text("Scan this code in Tink to connect")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !tailscaleIP.isEmpty {
                Text(tailscaleIP)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .task {
            tailscaleIP = await getTailscaleIP() ?? ""
        }
    }

    private var qrPayload: String? {
        guard !tailscaleIP.isEmpty else { return nil }
        let dict: [String: Any] = [
            "host": tailscaleIP,
            "port": Int(port),
            "token": token,
            "name": machineName
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    private var qrImage: NSImage? {
        guard let payload = qrPayload,
              let data = payload.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        let scale = 10.0
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }

    private func getTailscaleIP() async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/tailscale")
        process.arguments = ["ip", "-4"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == false ? output : nil
        } catch {
            return nil
        }
    }
}
