import SwiftUI

/// Same public **how-to** article as the consumer app (`Constants.helpHowToUseWearhouseURL`).
struct HowToUsePreluraView: View {
    var body: some View {
        HostedWebArticleView(
            title: L10n.string("How to use Prelura"),
            urlString: Constants.helpHowToUseWearhouseURL
        )
    }
}
