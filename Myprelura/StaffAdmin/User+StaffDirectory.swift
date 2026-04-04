import Foundation

extension User {
    /// Seed `UserProfileView` before the view model loads full GraphQL data (Myprelura People tab).
    static func fromStaffDirectory(username: String, row: UserAdminRow?) -> User {
        let u = (row?.username ?? username).trimmingCharacters(in: .whitespacesAndNewlines)
        let display = row?.displayName
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? u
        let pic = row?.profilePictureUrl ?? row?.thumbnailUrl
        let resolved = pic.flatMap { MediaURL.resolvedURL(from: $0)?.absoluteString }
        return User(
            userId: row?.id,
            username: u.isEmpty ? username : u,
            displayName: display,
            avatarURL: resolved,
            bio: nil,
            location: nil,
            listingsCount: row?.activeListings ?? 0,
            followingsCount: row?.noOfFollowing ?? 0,
            followersCount: row?.noOfFollowers ?? 0,
            isStaff: row?.isStaff ?? false,
            isVerified: row?.isVerified ?? false,
            isVacationMode: false,
            isMultibuyEnabled: false,
            isFollowing: nil
        )
    }
}
