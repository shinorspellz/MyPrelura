import SwiftUI
import AVKit

/// Full-screen looping video background. Use for login/signup screens.
struct VideoBackgroundView: View {
    let videoURL: URL?
    /// Optional dim overlay (e.g. black 0.4) so content is readable.
    var overlayOpacity: Double = 0.4

    var body: some View {
        ZStack {
            if let url = videoURL {
                LoopingVideoPlayerView(url: url)
                    .ignoresSafeArea()
                Color.black.opacity(overlayOpacity)
                    .ignoresSafeArea()
            } else {
                Theme.Colors.background
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Looping AVPlayer (UIViewRepresentable)
private struct LoopingVideoPlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIView {
        let view = PlayerView()
        view.setupPlayer(url: url)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private final class PlayerView: UIView {
    private var playerLooper: AVPlayerLooper?

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
    }

    func setupPlayer(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        queuePlayer.isMuted = true
        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        (layer as? AVPlayerLayer)?.player = queuePlayer
        (layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill
        queuePlayer.play()
    }
}

// MARK: - Bundle helpers for auth videos
enum AuthVideo {
    /// Signup video filename (from Videos/Signup folder; bundle may flatten so we identify by name).
    private static let signupVideoFileName = "206e4bb1-6b72-4d5a-b156-1708a62781a1.mp4"

    /// Random video for login (from Videos/Login; bundle may flatten so we exclude signup and pick one).
    static func randomLoginVideoURL() -> URL? {
        let all = Bundle.main.urls(forResourcesWithExtension: "mp4", subdirectory: nil) ?? []
        let login = all.filter { $0.lastPathComponent != signupVideoFileName }
        return login.isEmpty ? all.randomElement() : login.randomElement()
    }

    /// Video for signup (from Videos/Signup).
    static func signupVideoURL() -> URL? {
        if let url = Bundle.main.url(forResource: "206e4bb1-6b72-4d5a-b156-1708a62781a1", withExtension: "mp4", subdirectory: nil) {
            return url
        }
        return Bundle.main.urls(forResourcesWithExtension: "mp4", subdirectory: nil)?
            .first { $0.lastPathComponent == signupVideoFileName }
    }
}
