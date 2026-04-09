import SwiftUI

/// Central router for navigation. Only root screens live in the tab’s NavigationStack; everything else is pushed via these routes.
enum AppRoute: Hashable {
    case itemDetail(Item)
    /// `isArchived`: user opened the thread from the archived inbox list (show Restore in the chat menu).
    case conversation(Conversation, isArchived: Bool)
    case menu(MenuContext)
    case reviews(username: String, rating: Double)
}

/// Context passed when pushing Menu (profile menu with listing counts and flags).
struct MenuContext: Hashable {
    var listingCount: Int
    var isMultiBuyEnabled: Bool
    var isVacationMode: Bool
    var username: String?
}
