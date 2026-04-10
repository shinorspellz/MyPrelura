//
//  SplashView.swift
//  Myprelura
//
//  Splash: black background, WH monogram + WEARHOUSE sub-mark (staggered), **Pro** badge; "by Voltis Labs".
//

import SwiftUI

/// Staff app splash: same vector lockup as consumer + trailing **Pro** on the sub row.
struct SplashView: View {
    var onFinish: () -> Void

    @State private var phase: Phase = .hidden
    @State private var footerVisible = false

    private enum Phase {
        case hidden
        case mainVisible
        case allVisible
        case exiting
    }

    private let mainInDuration: Double = 0.6
    private let subStagger: Double = 0.18
    private let subInDuration: Double = 0.55
    private let holdDuration: Double = 1.2
    private let logoOutDuration: Double = 0.5

    private let splashMarkMaxWidth: CGFloat = 215.6 * 1.1

    private let whMonogramViewBoxSize: CGSize = CGSize(width: 409, height: 218)
    private let subWordmarkViewBoxSize: CGSize = CGSize(width: 246, height: 22)

    private var splashMainRenderedHeight: CGFloat {
        splashMarkMaxWidth * (whMonogramViewBoxSize.height / whMonogramViewBoxSize.width)
    }

    private var splashSubMarkMaxHeight: CGFloat {
        splashMainRenderedHeight / 10
    }

    private let splashMarkToSubSpacing: CGFloat = 36

    /// **Pro** label sized to the sub-mark cap height.
    private var splashProFontSize: CGFloat {
        max(11, min(16, splashSubMarkMaxHeight * 0.92))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: splashMarkToSubSpacing) {
                    Image("WearhouseSplashMain")
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(
                            whMonogramViewBoxSize.width / whMonogramViewBoxSize.height,
                            contentMode: .fit
                        )
                        .frame(maxWidth: splashMarkMaxWidth)
                        .scaleEffect(mainScale)
                        .opacity(mainOpacity)

                    HStack(alignment: .bottom, spacing: 10) {
                        Image("WearhouseSplashSub")
                            .resizable()
                            .renderingMode(.original)
                            .aspectRatio(
                                subWordmarkViewBoxSize.width / subWordmarkViewBoxSize.height,
                                contentMode: .fit
                            )
                            .frame(maxHeight: splashSubMarkMaxHeight)

                        Text("Pro")
                            .font(.system(size: splashProFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.primaryColor.opacity(0.92))
                            .padding(.bottom, 1)
                    }
                    .scaleEffect(subScale)
                    .opacity(subOpacity)
                }
                Spacer()
                Text("by Voltis Labs")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.7))
                    .opacity(footerVisible ? 1 : 0)
                    .scaleEffect(footerVisible ? 1 : 0.92)
                    .padding(.bottom, 32)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startAnimation()
        }
    }

    private var mainOpacity: Double {
        switch phase {
        case .hidden: return 0
        case .mainVisible, .allVisible: return 1
        case .exiting: return 0
        }
    }

    private var mainScale: CGFloat {
        switch phase {
        case .hidden: return 0.92
        case .mainVisible, .allVisible: return 1.0
        case .exiting: return 1.04
        }
    }

    private var subOpacity: Double {
        switch phase {
        case .hidden, .mainVisible: return 0
        case .allVisible: return 1
        case .exiting: return 0
        }
    }

    private var subScale: CGFloat {
        switch phase {
        case .hidden, .mainVisible: return 0.92
        case .allVisible: return 1.0
        case .exiting: return 1.04
        }
    }

    private func startAnimation() {
        withAnimation(.easeInOut(duration: mainInDuration)) {
            phase = .mainVisible
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + mainInDuration + subStagger) {
            withAnimation(.easeInOut(duration: subInDuration)) {
                phase = .allVisible
            }
        }
        let allInDone = mainInDuration + subStagger + subInDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + allInDone) {
            withAnimation(.easeInOut(duration: mainInDuration)) {
                footerVisible = true
            }
        }
        let totalBeforeExit = allInDone + holdDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + totalBeforeExit) {
            withAnimation(.easeInOut(duration: logoOutDuration)) {
                phase = .exiting
                footerVisible = false
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + totalBeforeExit + logoOutDuration) {
            onFinish()
        }
    }
}

#Preview {
    SplashView(onFinish: {})
}
