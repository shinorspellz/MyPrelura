import Foundation

/// A single review for a user (matches Flutter UserReviewModel / backend ReviewUserType).
struct UserReview: Identifiable {
    let id: String
    let rating: Int
    let comment: String
    let isAutoReview: Bool
    let dateCreated: Date
    let reviewerUsername: String
    let reviewerProfilePictureUrl: String?
}
