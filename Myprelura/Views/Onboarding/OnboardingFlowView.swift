import SwiftUI

/// Post-login welcome onboarding. Try Cart story is shown when entering Shop All (`AppBannerPolicy` + `TryCartOnboardingView`).
struct OnboardingFlowView: View {
    var onComplete: () -> Void

    var body: some View {
        OnboardingView(onComplete: onComplete)
    }
}

#Preview {
    OnboardingFlowView(onComplete: {})
}
