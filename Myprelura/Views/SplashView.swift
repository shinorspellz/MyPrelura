import SwiftUI

/// Same treatment as `PreluraSwift.SplashView`: black background, `SplashLogo` template in primary colour, Voltis footer.
struct SplashView: View {
    var onFinish: () -> Void

    @State private var phase: Phase = .hidden
    @State private var footerVisible = false

    private enum Phase {
        case hidden
        case visible
        case exiting
    }

    private let logoInDuration: Double = 0.6
    private let holdDuration: Double = 1.2
    private let logoOutDuration: Double = 0.5

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                Image("SplashLogo")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Theme.primaryColor)
                    .scaledToFit()
                    .frame(maxWidth: 280)
                    .scaleEffect(phase == .hidden ? 0.92 : (phase == .exiting ? 1.04 : 1.0))
                    .opacity(phase == .hidden ? 0 : (phase == .exiting ? 0 : 1))
                Spacer()
                Text("by Voltis Labs")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(footerVisible ? 1 : 0)
                    .scaleEffect(footerVisible ? 1 : 0.92)
                    .padding(.bottom, 32)
            }
        }
        .ignoresSafeArea()
        .onAppear { startAnimation() }
    }

    private func startAnimation() {
        withAnimation(.easeInOut(duration: logoInDuration)) {
            phase = .visible
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + logoInDuration) {
            withAnimation(.easeInOut(duration: logoInDuration)) {
                footerVisible = true
            }
        }
        let total = logoInDuration + holdDuration + logoOutDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + logoInDuration + holdDuration) {
            withAnimation(.easeInOut(duration: logoOutDuration)) {
                phase = .exiting
                footerVisible = false
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + total) {
            onFinish()
        }
    }
}
