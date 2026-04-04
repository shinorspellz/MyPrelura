import Foundation

/// Destinations for profile menu and submenus (matches Flutter menu structure).
enum MenuDestination: Identifiable, Hashable {
    case shopValue
    case orders
    case favourites
    case multiBuyDiscounts
    case vacationMode
    case inviteFriend
    case helpCentre
    case aboutPrelura
    case settings
    case logout
    
    /// Submenu for Settings (Flutter SettingScreen)
    case accountSettings
    case shippingAddress
    case appearance
    case profileDetails
    case payments
    case postage
    case securityPrivacy
    case identityVerification
    case pushNotifications
    case emailNotifications
    case adminActions
    
    /// Submenu for About Prelura
    case howToUsePrelura
    case legalInformation
    
    var id: String { "\(self)" }
}
