import SwiftUI

/// Animated pixel art cat logo matching the Familiar brand.
/// Uses sprite images with nearest-neighbor scaling for crispy pixels.
/// Eyes blink naturally, ears twitch occasionally (future: ear sprites).
struct PixelCatView: View {
    let size: CGFloat

    @State private var eyeState: EyeState = .open
    @State private var blinkTimer: Timer?

    enum EyeState {
        case open, half, closed

        var imageName: String {
            switch self {
            case .open: return "cat-open"
            case .half: return "cat-half"
            case .closed: return "cat-closed"
            }
        }
    }

    init(size: CGFloat = 60) {
        self.size = size
    }

    var body: some View {
        Image(eyeState.imageName)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(height: size)
            .onAppear { startAnimations() }
            .onDisappear { stopAnimations() }
    }

    private func startAnimations() {
        scheduleBlink()
    }

    private func scheduleBlink() {
        let delay = Double.random(in: 2.5...5.0)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            Task { @MainActor in
                await doBlink()
                if Double.random(in: 0...1) < 0.3 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    await doBlink()
                }
                scheduleBlink()
            }
        }
    }

    @MainActor
    private func doBlink() async {
        eyeState = .half
        try? await Task.sleep(nanoseconds: 60_000_000)
        eyeState = .closed
        try? await Task.sleep(nanoseconds: 80_000_000)
        eyeState = .half
        try? await Task.sleep(nanoseconds: 60_000_000)
        eyeState = .open
    }

    private func stopAnimations() {
        blinkTimer?.invalidate()
    }
}

#Preview {
    VStack(spacing: 20) {
        PixelCatView(size: 80)
        PixelCatView(size: 40)
            .padding()
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .padding(40)
}
