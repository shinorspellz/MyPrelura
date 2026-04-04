import SwiftUI
import Combine

private struct OptionalTabCoordinatorKey: EnvironmentKey {
    static let defaultValue: TabCoordinator? = nil
}

extension EnvironmentValues {
    var optionalTabCoordinator: TabCoordinator? {
        get { self[OptionalTabCoordinatorKey.self] }
        set { self[OptionalTabCoordinatorKey.self] = newValue }
    }
}

/// Coordinates tab bar taps with scroll-to-top and refresh. When user taps the same tab:
/// - First tap: scroll to top (or no-op if already at top)
/// - Second tap: refresh
final class TabCoordinator: ObservableObject {
    @Published var selectedTab: Int = 0
    @Published var readyForRefresh: Set<Int> = []
    /// When set, Inbox should navigate to this conversation (e.g. after sending an offer).
    @Published var pendingOpenConversation: Conversation?
    /// After multi-seller checkout: show Inbox list (new threads) instead of opening one chat.
    @Published var openInboxListOnly: Bool = false
    /// When true, the next chat load should treat a single REJECTED/CANCELLED offer as PENDING (we just sent from product page).
    @Published var pendingOfferJustSent: Bool = false
    /// Conversation id that `pendingOfferJustSent` applies to (avoids wrong "You offered" on other chats).
    @Published var pendingOfferConversationId: String?
    /// When set with pendingOfferJustSent, use this as the offer price when building the first offer (API may return wrong value).
    @Published var pendingOfferPrice: Double?
    /// When user leaves a chat, store last message preview so the list can show it immediately without waiting for refetch.
    @Published var lastMessagePreviewForConversation: (id: String, text: String, date: Date)?
    /// Incremented from chat (offers/messages) so the inbox list refetches and re-sorts without waiting for `onDisappear`.
    @Published private(set) var inboxListRefreshNonce: Int = 0
    /// Set after archive from chat toolbar (server already archived). Inbox applies optimistic list update + undo toast.
    @Published var pendingArchiveWithUndo: Conversation?
    /// Set from product options ("Copy to a new listing"); Sell tab consumes once then clears.
    @Published var pendingSellPrefill: SellFormPrefill?

    func requestInboxListRefresh() {
        inboxListRefreshNonce += 1
    }
    /// Per-tab: true when scroll view is at top. Used to decide: at top → refresh on tap; not at top → scroll first, refresh on second tap.
    private var atTop: [Int: Bool] = [:]

    private var scrollToTopActions: [Int: () -> Void] = [:]
    private var refreshActions: [Int: () -> Void] = [:]

    func registerScrollToTop(tab: Int, action: @escaping () -> Void) {
        scrollToTopActions[tab] = action
    }

    func registerRefresh(tab: Int, action: @escaping () -> Void) {
        refreshActions[tab] = action
    }

    func reportAtTop(tab: Int, isAtTop: Bool) {
        atTop[tab] = isAtTop
    }

    func handleTabTap(_ tab: Int) {
        if tab != selectedTab {
            selectedTab = tab
            readyForRefresh.removeAll()
            HapticManager.tabTap()
            return
        }

        // Same tab tapped
        if readyForRefresh.contains(tab) {
            readyForRefresh.remove(tab)
            refreshActions[tab]?()
            HapticManager.refresh()
            return
        }

        if atTop[tab] == true {
            refreshActions[tab]?()
            HapticManager.refresh()
            return
        }

        scrollToTopActions[tab]?()
        readyForRefresh.insert(tab)
        HapticManager.tabTap()
    }

    func selectTab(_ tab: Int) {
        selectedTab = tab
    }
}
