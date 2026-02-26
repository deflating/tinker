import SwiftUI
import AVFoundation

/// Camera-based QR code scanner that parses Tinker pairing payloads.
struct QRScannerView: View {
    var connection: TinkerConnection
    @Environment(\.dismiss) private var dismiss
    @State private var scannedPayload: PairingPayload?
    @State private var errorMessage: String?
    @State private var isPairing = false

    var body: some View {
        NavigationStack {
            ZStack {
                CameraPreview(onQRCode: handleScannedCode)
                    .ignoresSafeArea()

                VStack {
                    Spacer()

                    if let payload = scannedPayload {
                        pairedCard(payload)
                    } else if let errorMessage {
                        errorCard(errorMessage)
                    } else {
                        instructionCard
                    }
                }
                .padding()
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Cards

    private var instructionCard: some View {
        Text("Point your camera at the QR code shown in Tinker")
            .font(.subheadline)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func pairedCard(_ payload: PairingPayload) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
            Text("Paired with \(payload.name)")
                .font(.headline)
            Text("Connecting...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            // Reset to allow re-scanning
            errorMessage = nil
            scannedPayload = nil
        }
    }

    // MARK: - QR Handling

    private func handleScannedCode(_ code: String) {
        guard scannedPayload == nil, !isPairing else { return }
        isPairing = true

        guard let data = code.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PairingPayload.self, from: data) else {
            errorMessage = "Invalid QR code. Make sure you're scanning a Tinker pairing code."
            isPairing = false
            return
        }

        scannedPayload = payload

        // Save token to local keychain
        connection.setToken(payload.token)

        // Save as a host
        let saved = SavedHost(name: payload.name, host: payload.host, port: payload.port)
        connection.saveHost(saved)

        // Connect
        connection.connect(host: payload.host, port: payload.port, name: payload.name)

        // Dismiss after short delay so user sees the success state
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }
}

// MARK: - Pairing Payload

struct PairingPayload: Codable {
    let host: String
    let port: UInt16
    let token: String
    let name: String
}

// MARK: - Camera Preview (AVFoundation)

struct CameraPreview: UIViewRepresentable {
    let onQRCode: (String) -> Void

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView(onQRCode: onQRCode)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

class CameraPreviewUIView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let onQRCode: (String) -> Void
    private var hasDelivered = false

    init(onQRCode: @escaping (String) -> Void) {
        self.onQRCode = onQRCode
        super.init(frame: .zero)
        setupCamera()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            metadataOutput.metadataObjectTypes = [.qr]
        }

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasDelivered,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        hasDelivered = true
        captureSession.stopRunning()
        onQRCode(value)
    }

    deinit {
        captureSession.stopRunning()
    }
}
