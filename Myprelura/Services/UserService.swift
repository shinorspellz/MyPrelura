import Foundation
import Combine

@MainActor
class UserService: ObservableObject {
    private var client: GraphQLClient
    
    init(client: GraphQLClient? = nil) {
        self.client = client ?? GraphQLClient()
        // Try to load auth token from UserDefaults
        if let token = UserDefaults.standard.string(forKey: "AUTH_TOKEN") {
            self.client.setAuthToken(token)
        }
    }
    
    func updateAuthToken(_ token: String?) {
        client.setAuthToken(token)
    }
    
    func getUser(username: String? = nil) async throws -> User {
        let query = """
        query ViewMe {
          viewMe {
            id
            username
            displayName
            fullName
            profilePictureUrl
            bio
            email
            gender
            dob
            phone {
              countryCode
              number
            }
            location {
              locationName
            }
            listing
            noOfFollowing
            noOfFollowers
            isVacationMode
            isMultibuyEnabled
            isStaff
            isVerified
            reviewStats {
              noOfReviews
              rating
            }
            shippingAddress
            meta
          }
        }
        """
        
        let response: GetUserResponse = try await client.execute(
            query: query,
            responseType: GetUserResponse.self
        )
        
        guard let userData = response.viewMe else {
            throw UserError.userNotFound
        }
        
        // Extract location name from location object
        let locationName = userData.location?.locationName
        
        // Extract review stats
        let reviewCount = userData.reviewStats?.noOfReviews ?? 0
        let rating = userData.reviewStats?.rating ?? 5.0
        
        // Convert id to string
        let idString: String
        if let anyCodable = userData.id {
            if let intValue = anyCodable.value as? Int {
                idString = String(intValue)
            } else if let stringValue = anyCodable.value as? String {
                idString = stringValue
            } else {
                idString = String(describing: anyCodable.value)
            }
        } else {
            idString = ""
        }
        
        let phoneDisplay: String? = {
            guard let phone = userData.phone else { return nil }
            let code = phone.countryCode ?? ""
            let num = phone.number ?? ""
            if code.isEmpty && num.isEmpty { return nil }
            if code.isEmpty { return num }
            return "+\(code) \(num)"
        }()
        let dobDate: Date? = {
            guard let dob = userData.dob else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
            if let d = formatter.date(from: dob) { return d }
            let fallback = DateFormatter()
            fallback.dateFormat = "yyyy-MM-dd"
            return fallback.date(from: dob)
        }()

        let postageOptions = SellerPostageOptions.from(decoded: userData.meta?.value?.postage)
        let payoutBankAccount = PayoutBankAccountDisplay.from(decoded: userData.meta?.value?.payoutBankAccount)
        return User(
            id: UUID(uuidString: idString) ?? UUID(),
            username: userData.username ?? "",
            displayName: userData.displayName ?? "",
            avatarURL: userData.profilePictureUrl,
            bio: userData.bio,
            location: locationName,
            locationAbbreviation: extractLocationAbbreviation(from: locationName),
            rating: rating,
            reviewCount: reviewCount,
            listingsCount: userData.listing ?? 0,
            followingsCount: userData.noOfFollowing ?? 0,
            followersCount: userData.noOfFollowers ?? 0,
            isStaff: userData.isStaff ?? false,
            isVerified: userData.isVerified ?? false,
            isVacationMode: userData.isVacationMode ?? false,
            isMultibuyEnabled: userData.isMultibuyEnabled ?? false,
            email: userData.email,
            phoneDisplay: phoneDisplay,
            dateOfBirth: dobDate,
            gender: userData.gender,
            shippingAddress: parseShippingAddress(userData.shippingAddress?.normalizedJSONString),
            postageOptions: postageOptions,
            payoutBankAccount: payoutBankAccount
        )
    }
    
    /// Fetch another user's profile by username (for profile screen: bio, location, stats). Uses backend query getUser(username: String!).
    func getUserByUsername(_ username: String) async throws -> User {
        let query = """
        query GetUser($username: String!) {
          getUser(username: $username) {
            id
            username
            displayName
            fullName
            profilePictureUrl
            bio
            location { locationName }
            listing
            noOfFollowing
            noOfFollowers
            isFollowing
            isVacationMode
            isMultibuyEnabled
            isVerified
            reviewStats { noOfReviews rating }
          }
        }
        """
        let variables: [String: Any] = ["username": username]
        let response: GetUserByUsernameResponse = try await client.execute(
            query: query,
            variables: variables,
            responseType: GetUserByUsernameResponse.self
        )
        guard let userData = response.getUser else {
            throw UserError.userNotFound
        }
        let locationName = userData.location?.locationName
        let reviewCount = userData.reviewStats?.noOfReviews ?? 0
        let rating = userData.reviewStats?.rating ?? 5.0
        let idString: String
        let userIdInt: Int?
        if let anyCodable = userData.id {
            if let intValue = anyCodable.value as? Int {
                idString = String(intValue)
                userIdInt = intValue
            } else if let stringValue = anyCodable.value as? String {
                idString = stringValue
                userIdInt = Int(stringValue)
            } else {
                idString = String(describing: anyCodable.value)
                userIdInt = nil
            }
        } else {
            idString = ""
            userIdInt = nil
        }
        return User(
            id: UUID(uuidString: idString) ?? UUID(),
            userId: userIdInt,
            username: userData.username ?? "",
            displayName: userData.displayName ?? "",
            avatarURL: userData.profilePictureUrl,
            bio: userData.bio,
            location: locationName,
            locationAbbreviation: extractLocationAbbreviation(from: locationName),
            rating: rating,
            reviewCount: reviewCount,
            listingsCount: userData.listing ?? 0,
            followingsCount: userData.noOfFollowing ?? 0,
            followersCount: userData.noOfFollowers ?? 0,
            isStaff: false,
            isVerified: userData.isVerified ?? false,
            isVacationMode: userData.isVacationMode ?? false,
            isMultibuyEnabled: userData.isMultibuyEnabled ?? false,
            email: nil,
            phoneDisplay: nil,
            dateOfBirth: nil,
            gender: nil,
            shippingAddress: nil,
            isFollowing: userData.isFollowing
        )
    }
    
    /// Fetch current user's earnings (networth, balance, etc.) for Shop Value screen. Matches Flutter userRepo.getUserEarning().
    func getUserEarnings() async throws -> UserEarnings {
        let query = """
        query UserEarnings {
          userEarnings {
            networth
            pendingPayments { quantity value }
            completedPayments { quantity value }
            earningsInMonth { quantity value }
            totalEarnings { quantity value }
          }
        }
        """
        let response: UserEarningsResponse = try await client.execute(
            query: query,
            responseType: UserEarningsResponse.self
        )
        guard let data = response.userEarnings else {
            throw UserError.userNotFound
        }
        return UserEarnings(
            networth: data.networth ?? 0,
            pendingPayments: QuantityValue(quantity: data.pendingPayments?.quantity ?? 0, value: data.pendingPayments?.value ?? 0),
            completedPayments: QuantityValue(quantity: data.completedPayments?.quantity ?? 0, value: data.completedPayments?.value ?? 0),
            earningsInMonth: QuantityValue(quantity: data.earningsInMonth?.quantity ?? 0, value: data.earningsInMonth?.value ?? 0),
            totalEarnings: QuantityValue(quantity: data.totalEarnings?.quantity ?? 0, value: data.totalEarnings?.value ?? 0)
        )
    }
    
    /// Update profile. Matches Flutter userRepo.updateProfile(Variables$Mutation$UpdateProfile(...)).
    /// Pass only fields that changed; nil means don't update.
    /// Profile-only fields: username, bio, location (also used by Profile settings).
    func updateProfile(
        isVacationMode: Bool? = nil,
        displayName: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        gender: String? = nil,
        dob: Date? = nil,
        phoneNumber: (countryCode: String, number: String)? = nil,
        otp: String? = nil,
        bio: String? = nil,
        username: String? = nil,
        location: String? = nil,
        shippingAddress: ShippingAddress? = nil,
        meta: [String: Any]? = nil,
        fcmToken: String? = nil
    ) async throws {
        let mutation = """
        mutation UpdateProfile(
          $isVacationMode: Boolean
          $displayName: String
          $firstName: String
          $lastName: String
          $gender: String
          $dob: String
          $phoneNumber: PhoneInputType
          $otp: String
          $bio: String
          $username: String
          $location: LocationInputType
          $shippingAddress: ShippingAddressInputType
          $meta: JSONString
          $fcmToken: String
        ) {
          updateProfile(
            isVacationMode: $isVacationMode
            displayName: $displayName
            firstName: $firstName
            lastName: $lastName
            gender: $gender
            dob: $dob
            phoneNumber: $phoneNumber
            otp: $otp
            bio: $bio
            username: $username
            location: $location
            shippingAddress: $shippingAddress
            meta: $meta
            fcmToken: $fcmToken
          ) {
            message
          }
        }
        """
        var variables: [String: Any] = [:]
        if let v = isVacationMode { variables["isVacationMode"] = v }
        if let v = displayName, !v.isEmpty { variables["displayName"] = v }
        if let v = firstName, !v.isEmpty { variables["firstName"] = v }
        if let v = lastName, !v.isEmpty { variables["lastName"] = v }
        if let v = gender, !v.isEmpty { variables["gender"] = v }
        if let d = dob {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            variables["dob"] = formatter.string(from: d)
        }
        if let p = phoneNumber {
            variables["phoneNumber"] = [
                "countryCode": p.countryCode,
                "number": p.number,
                "completed": "\(p.countryCode)\(p.number)"
            ]
        }
        if let otp, !otp.isEmpty { variables["otp"] = otp }
        if let v = bio { variables["bio"] = v }
        if let v = username, !v.isEmpty { variables["username"] = v }
        if let v = location?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            // Backend accounts_userlocation has NOT NULL latitude/longitude; send placeholders when only updating name.
            variables["location"] = [
                "locationName": v,
                "latitude": "0",
                "longitude": "0"
            ]
        }
        if let s = shippingAddress {
            variables["shippingAddress"] = [
                "address": s.address,
                "city": s.city,
                "country": s.country,
                "postcode": s.postcode
            ]
        }
        if let m = meta, !m.isEmpty {
            // Backend expects JSONString (a string), not a raw object.
            if let data = try? JSONSerialization.data(withJSONObject: m), let str = String(data: data, encoding: .utf8) {
                variables["meta"] = str
            }
        }
        if let token = fcmToken, !token.isEmpty { variables["fcmToken"] = token }
        _ = try await client.execute(
            query: mutation,
            variables: variables.isEmpty ? nil : variables,
            responseType: UpdateProfileResponse.self
        )
    }

    /// Debug: ask the API to send one real FCM to this user’s stored tokens (rate-limited server-side).
    func sendDebugTestPush() async throws -> (success: Bool, message: String?) {
        let mutation = """
        mutation SendDebugTestPush {
          sendDebugTestPush {
            success
            message
          }
        }
        """
        let response: SendDebugTestPushResponse = try await client.execute(
            query: mutation,
            responseType: SendDebugTestPushResponse.self
        )
        let p = response.sendDebugTestPush
        return (p?.success == true, p?.message)
    }

    /// Send a one-time OTP to a phone number for phone verification.
    func sendPhoneOtp(phoneNumber: String, channel: String = "SMS", action: String = "VERIFY") async throws {
        let mutation = """
        mutation SendSmsOtp($channel: SmsChannelChoicesEnum, $phoneNumber: String, $action: SmsActionChoicesEnum) {
          sendSmsOtp(channel: $channel, phoneNumber: $phoneNumber, action: $action) {
            success
            message
          }
        }
        """
        let response: SendSmsOtpResponse = try await client.execute(
            query: mutation,
            variables: [
                "channel": channel,
                "phoneNumber": phoneNumber,
                "action": action
            ],
            responseType: SendSmsOtpResponse.self
        )
        if response.sendSmsOtp?.success != true {
            throw UserError.backendMessage(response.sendSmsOtp?.message ?? "Could not send OTP.")
        }
    }

    /// Update only profile picture (and thumbnail). Matches Flutter updateProfile(profilePicture: Input$ProfilePictureInputType(...)).
    /// Call after uploading image via FileUploadService.uploadProfileImage.
    func updateProfilePicture(profilePictureUrl: String, thumbnailUrl: String) async throws {
        let mutation = """
        mutation UpdateProfilePicture($profilePicture: ProfilePictureInputType) {
          updateProfile(profilePicture: $profilePicture) {
            message
          }
        }
        """
        let variables: [String: Any] = [
            "profilePicture": [
                "profilePictureUrl": profilePictureUrl,
                "thumbnailUrl": thumbnailUrl
            ]
        ]
        _ = try await client.execute(
            query: mutation,
            variables: variables,
            responseType: UpdateProfileResponse.self
        )
    }

    /// Change email (backend sends verification). Matches Flutter changeEmail mutation.
    func changeEmail(_ email: String) async throws {
        let mutation = """
        mutation ChangeEmail($email: String) {
          changeEmail(email: $email) {
            message
          }
        }
        """
        _ = try await client.execute(
            query: mutation,
            variables: ["email": email],
            responseType: ChangeEmailResponse.self
        )
    }

    // MARK: - Security & Privacy (client-only; backend unchanged)

    /// Reset password. Matches Flutter passwordChange(oldPassword, newPassword).
    func passwordChange(currentPassword: String, newPassword: String) async throws {
        let mutation = """
        mutation PasswordChange($oldPassword: String!, $newPassword1: String!, $newPassword2: String!) {
          passwordChange(oldPassword: $oldPassword, newPassword1: $newPassword1, newPassword2: $newPassword2) {
            success
            errors
          }
        }
        """
        struct Payload: Decodable { let passwordChange: PasswordChangePayload? }
        struct PasswordChangePayload: Decodable { let success: Bool?; let errors: [String: String]? }
        let vars: [String: Any] = ["oldPassword": currentPassword, "newPassword1": newPassword, "newPassword2": newPassword]
        let response: Payload = try await client.execute(query: mutation, variables: vars, responseType: Payload.self)
        if response.passwordChange?.success != true, let err = response.passwordChange?.errors?.values.first {
            throw NSError(domain: "PasswordChange", code: -1, userInfo: [NSLocalizedDescriptionKey: err])
        }
    }

    /// Delete account. Matches Flutter deleteAccount(password).
    func deleteAccount(password: String) async throws {
        let mutation = """
        mutation DeleteAccount($password: String!) {
          deleteAccount(password: $password) {
            success
            errors
          }
        }
        """
        struct Payload: Decodable { let deleteAccount: DeleteAccountPayload? }
        struct DeleteAccountPayload: Decodable { let success: Bool?; let errors: [String: String]? }
        let response: Payload = try await client.execute(query: mutation, variables: ["password": password], responseType: Payload.self)
        if response.deleteAccount?.success != true, let err = response.deleteAccount?.errors?.values.first {
            throw NSError(domain: "DeleteAccount", code: -1, userInfo: [NSLocalizedDescriptionKey: err])
        }
    }

    /// Pause (archive) account. Backend: archiveAccount(password).
    func archiveAccount(password: String) async throws {
        let mutation = """
        mutation ArchiveAccount($password: String!) {
          archiveAccount(password: $password) {
            success
            errors
          }
        }
        """
        struct Payload: Decodable { let archiveAccount: ArchiveAccountPayload? }
        struct ArchiveAccountPayload: Decodable { let success: Bool?; let errors: [String: String]? }
        let response: Payload = try await client.execute(query: mutation, variables: ["password": password], responseType: Payload.self)
        if response.archiveAccount?.success != true, let err = response.archiveAccount?.errors?.values.first {
            throw NSError(domain: "ArchiveAccount", code: -1, userInfo: [NSLocalizedDescriptionKey: err])
        }
    }

    /// Recommended/top sellers for Discover "Top Shops". Matches Flutter getRecommendedSellers(pageNumber, pageCount).
    func getRecommendedSellers(pageNumber: Int = 1, pageCount: Int = 20) async throws -> [RecommendedSeller] {
        let query = """
        query RecommendedSellers($pageCount: Int, $pageNumber: Int) {
          recommendedSellers(pageCount: $pageCount, pageNumber: $pageNumber) {
            seller {
              id
              username
              displayName
              profilePictureUrl
            }
          }
        }
        """
        let variables: [String: Any] = ["pageNumber": pageNumber, "pageCount": pageCount]
        struct Payload: Decodable {
            let recommendedSellers: [RecommendedSellerRow]?
        }
        struct RecommendedSellerRow: Decodable {
            let seller: SellerRow?
        }
        struct SellerRow: Decodable {
            let id: AnyCodable?
            let username: String?
            let displayName: String?
            let profilePictureUrl: String?
        }
        let response: Payload = try await client.execute(query: query, variables: variables, responseType: Payload.self)
        return (response.recommendedSellers ?? []).compactMap { row -> RecommendedSeller? in
            guard let s = row.seller else { return nil }
            let idStr: String
            if let any = s.id {
                if let i = any.value as? Int { idStr = String(i) }
                else if let str = any.value as? String { idStr = str }
                else { idStr = "" }
            } else { idStr = "" }
            let user = User(
                id: UUID(uuidString: idStr) ?? UUID(),
                username: s.username ?? "",
                displayName: s.displayName ?? s.username ?? "",
                avatarURL: s.profilePictureUrl
            )
            return RecommendedSeller(
                seller: user,
                totalSales: nil,
                totalShopValue: nil,
                productViews: 0,
                sellerScore: 0,
                activeListings: 0
            )
        }
    }

    /// Fetch blocked users. Matches Flutter getBlockedUsers.
    func getBlockedUsers(pageNumber: Int = 1, pageCount: Int = 20, search: String? = nil) async throws -> [BlockedUser] {
        let query = """
        query BlockedUsers($pageNumber: Int, $pageCount: Int, $search: String) {
          blockedUsers(pageNumber: $pageNumber, pageCount: $pageCount, search: $search) {
            id
            username
            displayName
            profilePictureUrl
            thumbnailUrl
          }
          blockedUsersTotalNumber
        }
        """
        var vars: [String: Any] = ["pageNumber": pageNumber, "pageCount": pageCount]
        if let s = search, !s.isEmpty { vars["search"] = s }
        let response: BlockedUsersResponse = try await client.execute(query: query, variables: vars, responseType: BlockedUsersResponse.self)
        return (response.blockedUsers ?? []).compactMap { u in
            guard let id = u.id else { return nil }
            return BlockedUser(id: id, username: u.username ?? "", displayName: u.displayName ?? "", profilePictureUrl: u.profilePictureUrl, thumbnailUrl: u.thumbnailUrl)
        }
    }

    /// Fetch reviews for a user. Matches Flutter getUserReviews (query userReviews + userReviewsTotalNumber).
    func getUserReviews(username: String, pageNumber: Int = 1, pageCount: Int = 20) async throws -> (reviews: [UserReview], totalNumber: Int) {
        let query = """
        query UserReviews($username: String!, $pageCount: Int, $pageNumber: Int) {
          userReviews(username: $username, pageCount: $pageCount, pageNumber: $pageNumber) {
            id
            rating
            comment
            isAutoReview
            dateCreated
            reviewer {
              username
              profilePictureUrl
            }
          }
          userReviewsTotalNumber
        }
        """
        struct Payload: Decodable {
            let userReviews: [UserReviewRow]?
            let userReviewsTotalNumber: Int?
        }
        struct UserReviewRow: Decodable {
            let id: String?
            let rating: Int?
            let comment: String?
            let isAutoReview: Bool?
            let dateCreated: String?
            let reviewer: ReviewerRow?
        }
        struct ReviewerRow: Decodable {
            let username: String?
            let profilePictureUrl: String?
        }
        let variables: [String: Any] = ["username": username, "pageCount": pageCount, "pageNumber": pageNumber]
        let response: Payload = try await client.execute(query: query, variables: variables, responseType: Payload.self)
        let total = response.userReviewsTotalNumber ?? 0
        let reviews = (response.userReviews ?? []).compactMap { row -> UserReview? in
            let id = row.id ?? "\(row.reviewer?.username ?? "")-\(row.dateCreated ?? "")"
            guard !id.isEmpty else { return nil }
            let date: Date = {
                guard let s = row.dateCreated else { return Date() }
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = iso.date(from: s) { return d }
                iso.formatOptions = [.withInternetDateTime]
                return iso.date(from: s) ?? Date()
            }()
            return UserReview(
                id: id,
                rating: row.rating ?? 0,
                comment: row.comment ?? "",
                isAutoReview: row.isAutoReview ?? false,
                dateCreated: date,
                reviewerUsername: row.reviewer?.username ?? "",
                reviewerProfilePictureUrl: row.reviewer?.profilePictureUrl
            )
        }
        return (reviews, total)
    }

    func getMyReports() async throws -> [MyReportRow] {
        let query = """
        query MyReports {
          myReports {
            id
            publicId
            reportType
            reason
            context
            imagesUrl
            status
            dateCreated
            updatedAt
            accountReportedUsername
            productId
            productName
            supportConversationId
          }
        }
        """
        struct Payload: Decodable { let myReports: [MyReportRow]? }
        let response: Payload = try await client.execute(query: query, variables: nil, responseType: Payload.self)
        return response.myReports ?? []
    }

    /// Fetch list of followers for a user. Uses existing backend query if available.
    func getFollowers(username: String, pageNumber: Int = 1, pageCount: Int = 50) async throws -> [User] {
        let query = """
        query Followers($username: String!, $pageNumber: Int, $pageCount: Int) {
          followers(username: $username, pageNumber: $pageNumber, pageCount: $pageCount) {
            id
            username
            displayName
            profilePictureUrl
          }
        }
        """
        struct FollowersPayload: Decodable {
            let followers: [FollowersListRow]?
        }
        struct FollowersListRow: Decodable {
            let id: AnyCodable?
            let username: String?
            let displayName: String?
            let profilePictureUrl: String?
        }
        let variables: [String: Any] = ["username": username, "pageNumber": pageNumber, "pageCount": pageCount]
        let response: FollowersPayload = try await client.execute(query: query, variables: variables, responseType: FollowersPayload.self)
        return (response.followers ?? []).compactMap { row -> User? in
            let idString: String = {
                guard let any = row.id else { return UUID().uuidString }
                if let i = any.value as? Int { return String(i) }
                if let s = any.value as? String { return s }
                return String(describing: any.value)
            }()
            return User(
                id: UUID(uuidString: idString) ?? UUID(),
                username: row.username ?? "",
                displayName: row.displayName ?? row.username ?? "",
                avatarURL: row.profilePictureUrl,
                followingsCount: 0,
                followersCount: 0
            )
        }
    }

    /// Fetch list of users that the given user follows.
    func getFollowing(username: String, pageNumber: Int = 1, pageCount: Int = 50) async throws -> [User] {
        let query = """
        query Following($username: String!, $pageNumber: Int, $pageCount: Int) {
          following(username: $username, pageNumber: $pageNumber, pageCount: $pageCount) {
            id
            username
            displayName
            profilePictureUrl
          }
        }
        """
        struct FollowingPayload: Decodable {
            let following: [FollowingListRow]?
        }
        struct FollowingListRow: Decodable {
            let id: AnyCodable?
            let username: String?
            let displayName: String?
            let profilePictureUrl: String?
        }
        let variables: [String: Any] = ["username": username, "pageNumber": pageNumber, "pageCount": pageCount]
        let response: FollowingPayload = try await client.execute(query: query, variables: variables, responseType: FollowingPayload.self)
        return (response.following ?? []).compactMap { row -> User? in
            let idString: String = {
                guard let any = row.id else { return UUID().uuidString }
                if let i = any.value as? Int { return String(i) }
                if let s = any.value as? String { return s }
                return String(describing: any.value)
            }()
            return User(
                id: UUID(uuidString: idString) ?? UUID(),
                username: row.username ?? "",
                displayName: row.displayName ?? row.username ?? "",
                avatarURL: row.profilePictureUrl,
                followingsCount: 0,
                followersCount: 0
            )
        }
    }

    /// Unblock user. Matches Flutter blockUnblockUser(action: false) → blockUser: false.
    func unblockUser(userId: Int) async throws {
        let mutation = """
        mutation BlockUnblock($userId: Int!, $blockUser: Boolean!) {
          blockUnblock(userId: $userId, blockUser: $blockUser) {
            success
            message
          }
        }
        """
        struct Payload: Decodable { let blockUnblock: BlockUnblockPayload? }
        struct BlockUnblockPayload: Decodable { let success: Bool?; let message: String? }
        let response: Payload = try await client.execute(query: mutation, variables: ["userId": userId, "blockUser": false], responseType: Payload.self)
        if response.blockUnblock?.success != true {
            throw NSError(domain: "BlockUnblock", code: -1, userInfo: [NSLocalizedDescriptionKey: response.blockUnblock?.message ?? "Unblock failed"])
        }
    }

    /// Report a user/account. Matches Flutter reportAccount(reason, username, content?).
    func reportAccount(username: String, reason: String, content: String? = nil, imagesUrl: [String] = []) async throws -> SubmittedReportRef? {
        let mutation = """
        mutation ReportAccount($reason: String!, $username: String!, $content: String, $imagesUrl: [String]) {
          reportAccount(reason: $reason, username: $username, content: $content, imagesUrl: $imagesUrl) {
            success
            message
            reportId
            publicId
            supportConversationId
          }
        }
        """
        var variables: [String: Any] = ["reason": reason, "username": username, "imagesUrl": imagesUrl]
        if let c = content, !c.isEmpty { variables["content"] = c }
        struct Payload: Decodable { let reportAccount: ReportResult? }
        struct ReportResult: Decodable {
            let success: Bool?
            let message: String?
            let reportId: Int?
            let publicId: String?
            let supportConversationId: Int?
        }
        let response: Payload = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
        return response.reportAccount.map {
            SubmittedReportRef(
                reportId: $0.reportId,
                publicId: $0.publicId,
                supportConversationId: $0.supportConversationId
            )
        }
    }

    /// Rate a user after an order (e.g. rate seller as buyer). Matches Flutter rateUser(comment, orderId, rating, userId).
    func rateUser(comment: String, orderId: Int, rating: Int, userId: Int) async throws {
        let mutation = """
        mutation RateUser($comment: String!, $orderId: Int!, $rating: Int!, $userId: Int!) {
          rateUser(comment: $comment, orderId: $orderId, rating: $rating, userId: $userId) {
            success
            message
          }
        }
        """
        struct Payload: Decodable { let rateUser: RateUserPayload? }
        struct RateUserPayload: Decodable { let success: Bool?; let message: String? }
        let response: Payload = try await client.execute(
            query: mutation,
            variables: ["comment": comment, "orderId": orderId, "rating": min(5, max(1, rating)), "userId": userId],
            responseType: Payload.self
        )
        if response.rateUser?.success != true {
            throw NSError(domain: "RateUser", code: -1, userInfo: [NSLocalizedDescriptionKey: response.rateUser?.message ?? "Failed to submit rating"])
        }
    }

    /// Cancel an order. Matches Flutter cancelOrder(orderId, reason, notes, imagesUrl). Reason must be OrderCancellationReasonEnum raw value (e.g. CHANGED_MY_MIND, NOT_AS_DESCRIBED).
    func cancelOrder(orderId: Int, reason: String, notes: String, imagesUrl: [String] = []) async throws {
        let mutation = """
        mutation CancelOrder($orderId: Int!, $reason: OrderCancellationReasonEnum!, $notes: String!, $imagesUrl: [String]!) {
          cancelOrder(orderId: $orderId, reason: $reason, notes: $notes, imagesUrl: $imagesUrl) {
            success
          }
        }
        """
        struct Payload: Decodable { let cancelOrder: CancelOrderPayload? }
        struct CancelOrderPayload: Decodable { let success: Bool? }
        let response: Payload = try await client.execute(
            query: mutation,
            variables: ["orderId": orderId, "reason": reason, "notes": notes, "imagesUrl": imagesUrl],
            responseType: Payload.self
        )
        if response.cancelOrder?.success != true {
            throw NSError(domain: "CancelOrder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to cancel order"])
        }
    }

    /// Seller requests cancellation; buyer must approve (confirmed orders only).
    func sellerRequestOrderCancellation(orderId: Int, reason: String, notes: String, imagesUrl: [String] = []) async throws {
        let mutation = """
        mutation SellerRequestOrderCancellation($orderId: Int!, $reason: OrderCancellationReasonEnum!, $notes: String!, $imagesUrl: [String]!) {
          sellerRequestOrderCancellation(orderId: $orderId, reason: $reason, notes: $notes, imagesUrl: $imagesUrl) {
            success
          }
        }
        """
        struct Payload: Decodable { let sellerRequestOrderCancellation: SellerCancelReqPayload? }
        struct SellerCancelReqPayload: Decodable { let success: Bool? }
        let response: Payload = try await client.execute(
            query: mutation,
            variables: ["orderId": orderId, "reason": reason, "notes": notes, "imagesUrl": imagesUrl],
            responseType: Payload.self
        )
        if response.sellerRequestOrderCancellation?.success != true {
            throw NSError(domain: "SellerRequestOrderCancellation", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to request cancellation"])
        }
    }

    func approveOrderCancellation(orderId: Int) async throws {
        let mutation = """
        mutation ApproveOrderCancellation($orderId: Int!) {
          approveOrderCancellation(orderId: $orderId) { success }
        }
        """
        struct Payload: Decodable { let approveOrderCancellation: ApproveCancelPayload? }
        struct ApproveCancelPayload: Decodable { let success: Bool? }
        let response: Payload = try await client.execute(
            query: mutation,
            variables: ["orderId": orderId],
            responseType: Payload.self
        )
        if response.approveOrderCancellation?.success != true {
            throw NSError(domain: "ApproveOrderCancellation", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to approve cancellation"])
        }
    }

    func rejectOrderCancellation(orderId: Int) async throws {
        let mutation = """
        mutation RejectOrderCancellation($orderId: Int!) {
          rejectOrderCancellation(orderId: $orderId) { success }
        }
        """
        struct Payload: Decodable { let rejectOrderCancellation: RejectCancelPayload? }
        struct RejectCancelPayload: Decodable { let success: Bool? }
        let response: Payload = try await client.execute(
            query: mutation,
            variables: ["orderId": orderId],
            responseType: Payload.self
        )
        if response.rejectOrderCancellation?.success != true {
            throw NSError(domain: "RejectOrderCancellation", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decline cancellation"])
        }
    }

    /// Create a fresh order case and emit an order_issue chat event for buyer/seller conversation.
    func raiseOrderIssue(
        orderId: Int,
        issueType: String,
        description: String,
        imagesUrl: [String] = [],
        otherIssueDescription: String? = nil
    ) async throws -> RaiseOrderIssueResult {
        let mutation = """
        mutation CreateOrderCase(
          $orderId: Int!,
          $issueType: String!,
          $description: String!,
          $imagesUrl: [String]!,
          $otherIssueDescription: String
        ) {
          createOrderCase(
            orderId: $orderId,
            issueType: $issueType,
            description: $description,
            imagesUrl: $imagesUrl,
            otherIssueDescription: $otherIssueDescription
          ) {
            success
            message
            issueId
            publicId
            supportConversationId
          }
        }
        """
        struct Payload: Decodable { let createOrderCase: RaiseOrderIssueResult? }
        let variables: [String: Any?] = [
            "orderId": orderId,
            "issueType": issueType,
            "description": description,
            "imagesUrl": imagesUrl,
            "otherIssueDescription": otherIssueDescription
        ]
        let filtered = variables.reduce(into: [String: Any]()) { acc, kv in
            if let v = kv.value { acc[kv.key] = v } else { acc[kv.key] = NSNull() }
        }
        let response: Payload = try await client.execute(
            query: mutation,
            variables: filtered,
            responseType: Payload.self
        )
        guard let result = response.createOrderCase else {
            throw NSError(domain: "RaiseOrderIssue", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid createOrderCase response"])
        }
        if result.success != true {
            throw NSError(domain: "RaiseOrderIssue", code: -1, userInfo: [NSLocalizedDescriptionKey: result.message ?? "Failed to raise issue"])
        }
        return result
    }

    /// Seller: open or reuse persisted Prelura support thread for this order issue (mirrors buyer `createOrderCase` support chat).
    func ensureSellerOrderIssueSupportThread(issueId: Int) async throws -> Int {
        let mutation = """
        mutation EnsureSellerOrderIssueSupportThread($issueId: Int!) {
          ensureSellerOrderIssueSupportThread(issueId: $issueId) {
            success
            message
            supportConversationId
          }
        }
        """
        struct Row: Decodable {
            let success: Bool?
            let message: String?
            let supportConversationId: Int?
        }
        struct Payload: Decodable { let ensureSellerOrderIssueSupportThread: Row? }
        let response: Payload = try await client.execute(
            query: mutation,
            variables: ["issueId": issueId],
            responseType: Payload.self
        )
        guard let row = response.ensureSellerOrderIssueSupportThread else {
            throw NSError(domain: "EnsureSellerOrderIssueSupportThread", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        if row.success == true, let cid = row.supportConversationId {
            return cid
        }
        throw NSError(domain: "EnsureSellerOrderIssueSupportThread", code: -1, userInfo: [NSLocalizedDescriptionKey: row.message ?? "Could not open support chat"])
    }

    /// Fetch a single order case by issueId or publicId.
    func getOrderIssue(issueId: Int? = nil, publicId: String? = nil) async throws -> OrderIssueDetails? {
        let query = """
        query GetOrderCase($issueId: Int, $publicId: String) {
          orderCase(issueId: $issueId, publicId: $publicId) {
            id
            publicId
            issueType
            description
            imagesUrl
            otherIssueDescription
            status
            createdAt
            order { id }
            raisedBy { username }
          }
        }
        """
        struct Payload: Decodable { let orderCase: OrderIssueDetails? }
        let variables: [String: Any?] = [
            "issueId": issueId,
            "publicId": publicId
        ]
        let filtered = variables.reduce(into: [String: Any]()) { acc, kv in
            if let v = kv.value { acc[kv.key] = v } else { acc[kv.key] = NSNull() }
        }
        let response: Payload = try await client.execute(
            query: query,
            variables: filtered,
            responseType: Payload.self
        )
        return response.orderCase
    }

    /// Follow a user. Matches Flutter followUser(followedId).
    func followUser(followedId: Int) async throws {
        let mutation = """
        mutation FollowUser($followedId: Int!) {
          followUser(followedId: $followedId) {
            success
          }
        }
        """
        struct Payload: Decodable { let followUser: FollowResult? }
        struct FollowResult: Decodable { let success: Bool? }
        let response: Payload = try await client.execute(query: mutation, variables: ["followedId": followedId], responseType: Payload.self)
        if response.followUser?.success != true {
            throw NSError(domain: "FollowUser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to follow"])
        }
    }

    /// Unfollow a user. Matches Flutter unfollowUser(followedId).
    func unfollowUser(followedId: Int) async throws {
        let mutation = """
        mutation UnfollowUser($followedId: Int!) {
          unfollowUser(followedId: $followedId) {
            success
          }
        }
        """
        struct Payload: Decodable { let unfollowUser: UnfollowResult? }
        struct UnfollowResult: Decodable { let success: Bool? }
        let response: Payload = try await client.execute(query: mutation, variables: ["followedId": followedId], responseType: Payload.self)
        if response.unfollowUser?.success != true {
            throw NSError(domain: "UnfollowUser", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to unfollow"])
        }
    }

    /// Search members by name/username. Uses backend query searchUsers(search: String!). Matches Flutter SearchUser.
    func searchUsers(search: String) async throws -> [User] {
        let query = """
        query SearchUser($search: String!) {
          searchUsers(search: $search) {
            id
            username
            displayName
            profilePictureUrl
            noOfFollowing
            noOfFollowers
            isFollowing
            listing
            location { locationName }
            reviewStats { noOfReviews rating }
          }
        }
        """
        struct Payload: Decodable { let searchUsers: [UserProfileData]? }
        let response: Payload = try await client.execute(
            query: query,
            variables: ["search": search],
            responseType: Payload.self
        )
        guard let list = response.searchUsers else { return [] }
        return list.compactMap { userData -> User? in
            let idString: String
            let userIdInt: Int?
            if let anyCodable = userData.id {
                if let intValue = anyCodable.value as? Int {
                    idString = String(intValue)
                    userIdInt = intValue
                } else if let stringValue = anyCodable.value as? String {
                    idString = stringValue
                    userIdInt = Int(stringValue)
                } else {
                    idString = String(describing: anyCodable.value)
                    userIdInt = nil
                }
            } else {
                return nil
            }
            let username = userData.username ?? ""
            guard !username.isEmpty else { return nil }
            let locationName = userData.location?.locationName
            let reviewCount = userData.reviewStats?.noOfReviews ?? 0
            let rating = userData.reviewStats?.rating ?? 5.0
            return User(
                id: UUID(uuidString: idString) ?? UUID(),
                userId: userIdInt,
                username: username,
                displayName: userData.displayName ?? username,
                avatarURL: userData.profilePictureUrl,
                bio: userData.bio,
                location: locationName,
                locationAbbreviation: extractLocationAbbreviation(from: locationName),
                rating: rating,
                reviewCount: reviewCount,
                listingsCount: userData.listing ?? 0,
                followingsCount: userData.noOfFollowing ?? 0,
                followersCount: userData.noOfFollowers ?? 0,
                isStaff: false,
                isVacationMode: userData.isVacationMode ?? false,
                isMultibuyEnabled: userData.isMultibuyEnabled ?? false,
                email: nil,
                phoneDisplay: nil,
                dateOfBirth: nil,
                gender: nil,
                shippingAddress: nil,
                isFollowing: userData.isFollowing
            )
        }
    }

    /// Fetch current payment method. Matches Flutter getUserPaymentMethod (query userPaymentMethods).
    func getUserPaymentMethod() async throws -> PaymentMethod? {
        let query = """
        query UserPaymentMethods {
          userPaymentMethods {
            paymentMethodId
            last4Digits
            cardBrand
          }
        }
        """
        struct Payload: Decodable {
            let userPaymentMethods: RawPaymentMethod?
        }
        struct RawPaymentMethod: Decodable {
            let paymentMethodId: String?
            let last4Digits: String?
            let cardBrand: String?
        }
        let response: Payload = try await client.execute(query: query, variables: nil, responseType: Payload.self)
        guard let raw = response.userPaymentMethods,
              let id = raw.paymentMethodId, !id.isEmpty else {
            return nil
        }
        return PaymentMethod(
            paymentMethodId: id,
            last4Digits: raw.last4Digits ?? "••••",
            cardBrand: raw.cardBrand ?? "Card"
        )
    }

    /// Add payment method (Stripe payment method ID). Matches Flutter addPaymentMethod.
    func addPaymentMethod(paymentMethodId: String) async throws {
        let mutation = """
        mutation AddPaymentMethod($paymentMethodID: String!) {
          addPaymentMethod(paymentMethodId: $paymentMethodID) {
            success
          }
        }
        """
        struct Payload: Decodable { let addPaymentMethod: AddPaymentMethodPayload? }
        struct AddPaymentMethodPayload: Decodable { let success: Bool? }
        let response: Payload = try await client.execute(query: mutation, variables: ["paymentMethodID": paymentMethodId], responseType: Payload.self)
        if response.addPaymentMethod?.success != true {
            throw NSError(domain: "AddPaymentMethod", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to add payment method"])
        }
    }

    /// Delete payment method. Matches Flutter deletePaymentMethod.
    func deletePaymentMethod(paymentMethodId: String) async throws {
        let mutation = """
        mutation DeletePaymentMethod($paymentMethodID: String!) {
          deletePaymentMethod(paymentMethodId: $paymentMethodID) {
            success
            error
          }
        }
        """
        struct Payload: Decodable { let deletePaymentMethod: DeletePaymentMethodPayload? }
        struct DeletePaymentMethodPayload: Decodable { let success: Bool?; let error: String? }
        let response: Payload = try await client.execute(query: mutation, variables: ["paymentMethodID": paymentMethodId], responseType: Payload.self)
        if response.deletePaymentMethod?.success != true {
            throw NSError(domain: "DeletePaymentMethod", code: -1, userInfo: [NSLocalizedDescriptionKey: response.deletePaymentMethod?.error ?? "Failed to delete"])
        }
    }

    /// Clear payout bank account from user meta (same path as AddBankAccountView).
    func clearPayoutBankAccount() async throws {
        try await updateProfile(meta: ["payoutBankAccount": NSNull()])
    }

    /// Create a Stripe payment intent for an order. Matches Flutter createPaymentIntent. Returns clientSecret (for Stripe SDK) and paymentRef (for confirmPayment).
    func createPaymentIntent(orderId: Int, paymentMethodId: String) async throws -> (clientSecret: String, paymentRef: String) {
        NSLog("[PAY_DEBUG] createPaymentIntent orderId=%d", orderId)
        let mutation = """
        mutation CreatePaymentIntent($orderId: Int!, $paymentMethodId: String!) {
          createPaymentIntent(orderId: $orderId, paymentMethodId: $paymentMethodId) {
            clientSecret
            paymentRef
          }
        }
        """
        struct Payload: Decodable { let createPaymentIntent: CreatePaymentIntentPayload? }
        struct CreatePaymentIntentPayload: Decodable {
            let clientSecret: String?
            let paymentRef: String?
        }
        let response: Payload = try await client.execute(
            query: mutation,
            variables: ["orderId": orderId, "paymentMethodId": paymentMethodId],
            responseType: Payload.self
        )
        guard let intent = response.createPaymentIntent,
              let ref = intent.paymentRef, !ref.isEmpty else {
            NSLog("[PAY_DEBUG] createPaymentIntent failed: no ref")
            throw NSError(domain: "CreatePaymentIntent", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create payment intent"])
        }
        let secret = intent.clientSecret ?? ""
        NSLog("[PAY_DEBUG] createPaymentIntent ok paymentRef=%@", ref)
        return (secret, ref)
    }

    /// Confirm payment after Stripe confirmation (or if backend allows). Matches Flutter confirmPayment.
    func confirmPayment(paymentRef: String) async throws -> (paymentStatus: String?, orderConfirmed: Bool?, message: String?) {
        NSLog("[PAY_DEBUG] confirmPayment called paymentRef=%@", paymentRef)
        let mutation = """
        mutation ConfirmPayment($paymentRef: String!) {
          confirmPayment(paymentRef: $paymentRef) {
            paymentStatus
            orderConfirmed
            message
          }
        }
        """
        struct Payload: Decodable { let confirmPayment: ConfirmPaymentPayload? }
        struct ConfirmPaymentPayload: Decodable {
            let paymentStatus: String?
            let orderConfirmed: Bool?
            let message: String?
        }
        let response: Payload = try await client.execute(query: mutation, variables: ["paymentRef": paymentRef], responseType: Payload.self)
        guard let confirm = response.confirmPayment else {
            NSLog("[PAY_DEBUG] confirmPayment invalid response")
            throw NSError(domain: "ConfirmPayment", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        NSLog("[PAY_DEBUG] confirmPayment result orderConfirmed=%@ paymentStatus=%@ message=%@", String(describing: confirm.orderConfirmed), confirm.paymentStatus ?? "nil", confirm.message ?? "nil")
        return (confirm.paymentStatus, confirm.orderConfirmed, confirm.message)
    }

    /// Generate shipping label for an order (seller). Matches Flutter generateShippingLabel.
    func generateShippingLabel(orderId: Int) async throws -> (success: Bool, labelUrl: String?, message: String?) {
        let mutation = """
        mutation GenerateShippingLabel($orderId: Int!) {
          generateShippingLabel(orderId: $orderId) {
            success
            labelUrl
            message
          }
        }
        """
        struct Payload: Decodable { let generateShippingLabel: GenerateShippingLabelPayload? }
        struct GenerateShippingLabelPayload: Decodable {
            let success: Bool?
            let labelUrl: String?
            let message: String?
        }
        let response: Payload = try await client.execute(query: mutation, variables: ["orderId": orderId], responseType: Payload.self)
        guard let gen = response.generateShippingLabel else {
            throw NSError(domain: "GenerateShippingLabel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        return (gen.success ?? false, gen.labelUrl, gen.message)
    }

    /// Confirm shipping (seller): carrier and tracking. Matches Flutter confirmShipping.
    func confirmShipping(orderId: Int, carrierName: String, trackingNumber: String, trackingUrl: String? = nil) async throws {
        let mutation = """
        mutation ConfirmShipping($orderId: Int!, $carrierName: String!, $trackingNumber: String!, $trackingUrl: String) {
          confirmShipping(orderId: $orderId, carrierName: $carrierName, trackingNumber: $trackingNumber, trackingUrl: $trackingUrl) {
            success
            message
          }
        }
        """
        struct Payload: Decodable { let confirmShipping: ConfirmShippingPayload? }
        struct ConfirmShippingPayload: Decodable { let success: Bool?; let message: String? }
        var variables: [String: Any] = ["orderId": orderId, "carrierName": carrierName, "trackingNumber": trackingNumber]
        if let url = trackingUrl, !url.isEmpty { variables["trackingUrl"] = url }
        let response: Payload = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
        if response.confirmShipping?.success != true {
            throw NSError(domain: "ConfirmShipping", code: -1, userInfo: [NSLocalizedDescriptionKey: response.confirmShipping?.message ?? "Failed to confirm shipping"])
        }
    }

    // MARK: - Multi-buy discounts (matches Flutter userMultibuyDiscounts / createMultibuyDiscount / deactivateMultibuyDiscounts)

    /// Fetch current user multi-buy discount tiers. userId nil = current user.
    func getMultibuyDiscounts(userId: Int? = nil) async throws -> [MultibuyDiscount] {
        let query = """
        query UserMultibuyDiscounts($userId: Int) {
          userMultibuyDiscounts(userId: $userId) {
            id
            minItems
            discountValue
            isActive
          }
        }
        """
        var variables: [String: Any] = [:]
        if let userId = userId { variables["userId"] = userId }
        struct Payload: Decodable {
            let userMultibuyDiscounts: [MultibuyDiscountRow]?
        }
        struct MultibuyDiscountRow: Decodable {
            let id: AnyCodable?
            let minItems: Int?
            let discountValue: DecimalStringOrNumber?
            let isActive: Bool?
        }
        let response: Payload = try await client.execute(query: query, variables: variables.isEmpty ? nil : variables, responseType: Payload.self)
        let rows = response.userMultibuyDiscounts ?? []
        return rows.compactMap { row in
            guard let minItems = row.minItems else { return nil }
            let idInt: Int? = row.id.flatMap { id in (id.value as? Int) ?? (id.value as? String).flatMap { Int($0) } }
            let valueStr = row.discountValue?.stringValue ?? "0"
            return MultibuyDiscount(
                id: idInt,
                minItems: minItems,
                discountValue: valueStr,
                isActive: row.isActive ?? true
            )
        }
    }

    /// Create or update multi-buy discount tiers. Each input: id nil = create, id set = update.
    func createOrUpdateMultibuyDiscount(inputs: [MultibuyDiscountInput]) async throws {
        let mutation = """
        mutation CreateMultibuyDiscount($inputs: [MultibuyInputType]!) {
          createMultibuyDiscount(inputs: $inputs) {
            success
          }
        }
        """
        let inputDicts: [[String: Any]] = inputs.map { input in
            var d: [String: Any] = [
                "minItems": input.minItems,
                "discountPercentage": input.discountPercentage,
                "isActive": input.isActive
            ]
            if let id = input.id { d["id"] = id }
            return d
        }
        struct Payload: Decodable {
            let createMultibuyDiscount: CreateMultibuyResult?
        }
        struct CreateMultibuyResult: Decodable {
            let success: Bool?
        }
        let response: Payload = try await client.execute(query: mutation, variables: ["inputs": inputDicts], responseType: Payload.self)
        if response.createMultibuyDiscount?.success != true {
            throw NSError(domain: "CreateMultibuyDiscount", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save multi-buy discounts"])
        }
    }

    // MARK: - User orders (matches Flutter userOrders query)

    /// Fetch orders for current user. isSeller true = Sold, false = Bought. Status filter is client-side (All / In Progress / Cancelled / Completed).
    func getUserOrders(isSeller: Bool, pageNumber: Int = 1, pageCount: Int = 50) async throws -> (orders: [Order], totalNumber: Int) {
        let query = """
        query UserOrders($filters: OrderFiltersInput, $pageCount: Int, $pageNumber: Int) {
          userOrders(filters: $filters, pageCount: $pageCount, pageNumber: $pageNumber) {
            id
            publicId
            priceTotal
            discountPrice
            status
            createdAt
            updatedAt
            shippingAddress
            shipmentService
            shipmentEstimatedDelivery
            trackingNumber
            trackingUrl
            buyerOrderCountWithSeller
            cancelledOrder { status requestedBySeller }
            user { id username displayName profilePictureUrl }
            products {
              id
              name
              imagesUrl
              price
              condition
              color
              style
              size { name }
              brand { name }
              materials { name }
            }
          }
          userOrdersTotalNumber
        }
        """
        let filters: [String: Any] = ["isSeller": isSeller]
        let variables: [String: Any] = [
            "filters": filters,
            "pageCount": pageCount,
            "pageNumber": pageNumber
        ]
        struct Payload: Decodable {
            let userOrders: [OrderRow]?
            let userOrdersTotalNumber: IntOrString?
        }
        struct OrderRow: Decodable {
            let id: AnyCodable?
            let publicId: String?
            let priceTotal: DecimalStringOrNumber?
            let discountPrice: DecimalStringOrNumber?
            let status: String?
            let createdAt: DateStringOrTimestamp?
            let updatedAt: DateStringOrTimestamp?
            let shippingAddress: String?
            let shipmentService: String?
            let shipmentEstimatedDelivery: DateStringOrTimestamp?
            let trackingNumber: String?
            let trackingUrl: String?
            let buyerOrderCountWithSeller: Int?
            let cancelledOrder: CancelledOrderRow?
            let user: OrderUserRow?
            let products: [OrderProductRow]?
        }
        struct CancelledOrderRow: Decodable {
            let status: String?
            let requestedBySeller: Bool?
        }
        struct OrderUserRow: Decodable {
            let id: AnyCodable?
            let username: String?
            let displayName: String?
            let profilePictureUrl: String?
        }
        struct OrderProductRow: Decodable {
            let id: AnyCodable?
            let name: String?
            let imagesUrl: [OrderImageUrlElement]?
            let price: DecimalStringOrNumber?
            let condition: String?
            let color: [String]?
            let style: String?
            let size: OrderProductSizeRow?
            let brand: OrderProductBrandRow?
            let materials: [OrderProductMaterialRow]?
        }
        struct OrderProductSizeRow: Decodable {
            let name: String?
        }
        struct OrderProductBrandRow: Decodable {
            let name: String?
        }
        struct OrderProductMaterialRow: Decodable {
            let name: String?
        }
        /// Accepts ISO8601 string or Unix timestamp (Double/Int).
        struct DateStringOrTimestamp: Decodable {
            let date: Date?
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) {
                    date = Self.parseISO8601(s)
                } else if let n = try? c.decode(Double.self) {
                    date = Date(timeIntervalSince1970: n)
                } else if let n = try? c.decode(Int.self) {
                    date = Date(timeIntervalSince1970: Double(n))
                } else {
                    date = nil
                }
            }
            static func parseISO8601(_ s: String) -> Date? {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = formatter.date(from: s) { return d }
                formatter.formatOptions = [.withInternetDateTime]
                return formatter.date(from: s)
            }
        }
        /// Accepts "url" string or object { "url": "..." }.
        struct OrderImageUrlElement: Decodable {
            let urlString: String?
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) {
                    urlString = s
                } else if let dict = try? c.decode([String: String].self), let u = dict["url"] {
                    urlString = u
                } else {
                    urlString = nil
                }
            }
        }
        struct IntOrString: Decodable {
            let intValue: Int
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let n = try? c.decode(Int.self) {
                    intValue = n
                } else if let s = try? c.decode(String.self), let n = Int(s) {
                    intValue = n
                } else {
                    intValue = 0
                }
            }
        }
        let response: Payload = try await client.execute(query: query, variables: variables, responseType: Payload.self)
        let rows = response.userOrders ?? []
        let orders = rows.compactMap { row -> Order? in
            guard let idVal = row.id?.value else { return nil }
            let idStr = (idVal as? Int).map { String($0) } ?? (idVal as? String) ?? String(describing: idVal)
            let otherParty: User? = row.user.map { u in
                let uid = (u.id?.value as? Int) ?? (u.id?.value as? String).flatMap { Int($0) }
                return User(
                    userId: uid,
                    username: u.username ?? "",
                    displayName: u.displayName ?? "",
                    avatarURL: u.profilePictureUrl
                )
            }
            let products: [OrderProductSummary] = (row.products ?? []).compactMap { p -> OrderProductSummary? in
                let pid = (p.id?.value as? Int).map { String($0) } ?? (p.id?.value as? String)
                guard let pid = pid else { return nil }
                let imgUrl: String? = {
                    guard let first = p.imagesUrl?.first, let s = first.urlString, !s.isEmpty else { return nil }
                    if s.hasPrefix("{"), let data = s.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let u = json["url"] as? String { return u }
                    return s
                }()
                let priceStr = p.price?.stringValue ?? ""
                return OrderProductSummary(
                    id: String(describing: pid),
                    name: p.name ?? "",
                    imageUrl: imgUrl,
                    price: priceStr,
                    condition: p.condition,
                    colors: p.color ?? [],
                    style: p.style,
                    size: p.size?.name,
                    brand: p.brand?.name,
                    materials: (p.materials ?? []).compactMap { $0.name }
                )
            }
            let createdAt = row.createdAt?.date ?? Self.parseCreatedAt(nil) ?? Date()
            let priceStr = row.priceTotal?.stringValue ?? "0"
            let cancellation: OrderCancellationSummary? = {
                guard let co = row.cancelledOrder, let st = co.status?.trimmingCharacters(in: .whitespacesAndNewlines), !st.isEmpty else { return nil }
                return OrderCancellationSummary(status: st.uppercased(), requestedBySeller: co.requestedBySeller ?? false)
            }()
            return Order(
                id: idStr,
                publicId: row.publicId,
                priceTotal: priceStr,
                discountPrice: row.discountPrice?.stringValue,
                status: row.status ?? "",
                createdAt: createdAt,
                otherParty: otherParty,
                products: products,
                shippingAddress: parseShippingAddress(row.shippingAddress),
                shipmentService: row.shipmentService,
                deliveryDate: row.shipmentEstimatedDelivery?.date,
                trackingNumber: row.trackingNumber,
                trackingUrl: row.trackingUrl,
                buyerOrderCountWithSeller: row.buyerOrderCountWithSeller,
                cancellation: cancellation
            )
        }
        let total = response.userOrdersTotalNumber?.intValue ?? 0
        return (orders, total)
    }

    /// Turn off all multi-buy discounts for the current user.
    func deactivateMultibuyDiscounts() async throws {
        let mutation = """
        mutation DeactivateMultibuyDiscounts {
          deactivateMultibuyDiscounts {
            success
          }
        }
        """
        struct Payload: Decodable {
            let deactivateMultibuyDiscounts: DeactivateResult?
        }
        struct DeactivateResult: Decodable {
            let success: Bool?
        }
        let response: Payload = try await client.execute(query: mutation, responseType: Payload.self)
        if response.deactivateMultibuyDiscounts?.success != true {
            throw NSError(domain: "DeactivateMultibuyDiscounts", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to turn off multi-buy discounts"])
        }
    }

    /// Parse shippingAddress from ViewMe (JSONString – JSON string from API).
    private func parseShippingAddress(_ value: String?) -> ShippingAddress? {
        guard let str = value, !str.isEmpty,
              let data = str.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return ShippingAddress(
            address: json["address"] as? String ?? "",
            city: json["city"] as? String ?? "",
            state: json["state"] as? String,
            country: json["country"] as? String ?? "GB",
            postcode: json["postcode"] as? String ?? ""
        )
    }

    private func extractLocationAbbreviation(from location: String?) -> String? {
        guard let location = location else { return nil }
        // Extract abbreviation (e.g., "London, United Kingdom" -> "LDN")
        let components = location.split(separator: ",")
        if let firstComponent = components.first {
            let words = firstComponent.split(separator: " ")
            if words.count > 1 {
                return words.compactMap { String($0.prefix(1)).uppercased() }.joined()
            }
            return String(firstComponent.prefix(3)).uppercased()
        }
        return nil
    }
    
    func getUserProducts(username: String? = nil) async throws -> [Item] {
        let query = """
        query UserProducts($username: String) {
          userProducts(username: $username) {
            id
            listingCode
            name
            description
            price
            discountPrice
            imagesUrl
            condition
            createdAt
            size {
              id
              name
            }
            brand {
              id
              name
            }
            customBrand
            likes
            views
            userLiked
            seller {
              id
              username
              displayName
              profilePictureUrl
              isVacationMode
            }
            category {
              id
              name
            }
            color
            status
          }
        }
        """
        
        var variables: [String: Any] = [:]
        if let username = username {
            variables["username"] = username
        }
        
        let response: UserProductsResponse = try await client.execute(
            query: query,
            variables: variables.isEmpty ? nil : variables,
            responseType: UserProductsResponse.self
        )
        
        guard let products = response.userProducts else {
            return []
        }
        
        return products.compactMap { product in
            // Convert id to string
            let idString: String
            if let anyCodable = product.id {
                if let intValue = anyCodable.value as? Int {
                    idString = String(intValue)
                } else if let stringValue = anyCodable.value as? String {
                    idString = stringValue
                } else {
                    idString = String(describing: anyCodable.value)
                }
            } else {
                return nil
            }
            
            // Extract image URLs from imagesUrl array
            let imageURLs = extractImageURLs(from: product.imagesUrl)
            let listDisplayURL = ProductListImageURL.preferredString(fromImagesUrlArray: product.imagesUrl) ?? imageURLs.first

            // Extract seller id (string for UUID, int for backend userId / multibuy)
            let sellerIdString: String
            let sellerUserIdInt: Int?
            if let sellerId = product.seller?.id {
                if let intValue = sellerId.value as? Int {
                    sellerIdString = String(intValue)
                    sellerUserIdInt = intValue
                } else if let stringValue = sellerId.value as? String {
                    sellerIdString = stringValue
                    sellerUserIdInt = Int(stringValue)
                } else {
                    sellerIdString = String(describing: sellerId.value)
                    sellerUserIdInt = nil
                }
            } else {
                sellerIdString = ""
                sellerUserIdInt = nil
            }
            
            // Parse discountPrice (it's a percentage string, e.g., "20" for 20% off)
            let originalPrice = product.price ?? 0.0
            let discountPercentage: Double? = {
                guard let discountPriceStr = product.discountPrice,
                      let discount = Double(discountPriceStr),
                      discount > 0 else {
                    return nil
                }
                return discount
            }()
            
            // Calculate final price: if discount exists, apply it; otherwise use original price
            let finalPrice: Double
            let itemOriginalPrice: Double?
            if let discount = discountPercentage {
                // Calculate discounted price: originalPrice - (originalPrice * discount / 100)
                finalPrice = originalPrice - (originalPrice * discount / 100)
                itemOriginalPrice = originalPrice
            } else {
                finalPrice = originalPrice
                itemOriginalPrice = nil
            }

            let listingCode: String? = {
                guard let lc = product.listingCode?.trimmingCharacters(in: .whitespacesAndNewlines), !lc.isEmpty else { return nil }
                return lc
            }()

            return Item(
                id: Item.id(fromProductId: idString),
                productId: idString,
                listingCode: listingCode,
                title: product.name ?? "",
                description: product.description ?? "",
                price: finalPrice,
                originalPrice: itemOriginalPrice,
                imageURLs: imageURLs,
                listDisplayImageURL: listDisplayURL,
                category: Category.fromName(product.category?.name ?? ""),
                categoryName: product.category?.name, // Store actual category name from API (subcategory)
                seller: User(
                    id: UUID(uuidString: sellerIdString) ?? UUID(),
                    userId: sellerUserIdInt,
                    username: product.seller?.username ?? "",
                    displayName: product.seller?.displayName ?? "",
                    avatarURL: product.seller?.profilePictureUrl,
                    isVacationMode: product.seller?.isVacationMode ?? false
                ),
                condition: product.condition ?? "",
                size: product.size?.name,
                brand: product.brand?.name ?? product.customBrand,
                colors: product.color ?? [],
                likeCount: product.likes ?? 0,
                views: product.views ?? 0,
                createdAt: Self.parseCreatedAt(product.createdAt) ?? Date(),
                isLiked: product.userLiked ?? false,
                status: product.status ?? "ACTIVE",
                sellCategoryBackendId: Self.graphQLStringId(product.category?.id),
                sellSizeBackendId: Self.graphQLIntId(product.size?.id)
            )
        }
    }

    private static func graphQLStringId(_ codable: AnyCodable?) -> String? {
        guard let v = codable?.value else { return nil }
        if let i = v as? Int { return String(i) }
        if let s = v as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
        return nil
    }

    private static func graphQLIntId(_ codable: AnyCodable?) -> Int? {
        guard let v = codable?.value else { return nil }
        if let i = v as? Int { return i }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
    
    private static func parseCreatedAt(_ iso8601: String?) -> Date? {
        guard let s = iso8601 else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: s) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: s)
    }
    
    private func extractImageURLs(from imagesUrl: [String]?) -> [String] {
        guard let imagesUrl = imagesUrl else { return [] }
        var urls: [String] = []
        for imageJson in imagesUrl {
            // imagesUrl contains JSON strings like '{"url":"...","thumbnail":"..."}'
            // Try to parse as JSON string
            if let data = imageJson.data(using: .utf8) {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let url = json["url"] as? String, !url.isEmpty {
                        urls.append(url)
                    }
                } catch {
                    // If JSON parsing fails, try using the string directly as URL (fallback)
                    // This handles cases where imagesUrl might already contain direct URLs
                    if !imageJson.isEmpty && (imageJson.hasPrefix("http://") || imageJson.hasPrefix("https://")) {
                        urls.append(imageJson)
                    }
                }
            } else {
                // If data conversion fails, try using the string directly as URL (fallback)
                if !imageJson.isEmpty && (imageJson.hasPrefix("http://") || imageJson.hasPrefix("https://")) {
                    urls.append(imageJson)
                }
            }
        }
        return urls
    }
}

struct GetUserResponse: Decodable {
    let viewMe: UserProfileData?
}

/// Response for GetUser(username: String!) query (other user's profile).
struct GetUserByUsernameResponse: Decodable {
    let getUser: UserProfileData?
}

/// GraphQL `JSONString` may be a string or an inline JSON object in the HTTP body.
struct GraphQLJSONStringOrObject: Decodable {
    let normalizedJSONString: String?

    private struct DynamicCodingKey: CodingKey, Hashable {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var dict: [String: Any] = [:]
            for key in keyed.allKeys {
                if let s = try? keyed.decode(String.self, forKey: key) {
                    dict[key.stringValue] = s
                } else if let i = try? keyed.decode(Int.self, forKey: key) {
                    dict[key.stringValue] = i
                } else if let d = try? keyed.decode(Double.self, forKey: key) {
                    dict[key.stringValue] = d
                } else if let b = try? keyed.decode(Bool.self, forKey: key) {
                    dict[key.stringValue] = b
                }
            }
            if JSONSerialization.isValidJSONObject(dict), let data = try? JSONSerialization.data(withJSONObject: dict) {
                normalizedJSONString = String(data: data, encoding: .utf8)
            } else {
                normalizedJSONString = nil
            }
            return
        }
        let c = try decoder.singleValueContainer()
        if try c.decodeNil() {
            normalizedJSONString = nil
            return
        }
        normalizedJSONString = try c.decode(String.self)
    }
}

struct UserProfileData: Decodable {
    let id: AnyCodable?
    let username: String?
    let displayName: String?
    let fullName: String?
    let profilePictureUrl: String?
    let bio: String?
    let email: String?
    let gender: String?
    let dob: String?  // ISO date string from API
    let phone: UserPhoneData?
    let shippingAddress: GraphQLJSONStringOrObject?
    let location: LocationData?
    let listing: Int?
    let noOfFollowing: Int?
    let noOfFollowers: Int?
    let isFollowing: Bool?
    let isVacationMode: Bool?
    let isMultibuyEnabled: Bool?
    let isStaff: Bool?
    let isVerified: Bool?
    let reviewStats: ReviewStatsData?
    /// Backend may send meta as object or JSON string; decoded safely so viewMe never fails.
    let meta: SafeMetaDecode?
}

struct UserPhoneData: Decodable {
    let countryCode: String?
    let number: String?
}

/// Shipping address (from ViewMe or for updateProfile). Backend input uses address, city, country, postcode only.
struct ShippingAddress: Hashable {
    var address: String
    var city: String
    var state: String?
    var country: String
    var postcode: String
}

/// Seller postage options stored in User.meta["postage"]. Used in PostageSettingsView and at checkout.
struct SellerPostageOptions: Hashable {
    var royalMailEnabled: Bool
    var royalMailStandardPrice: Double?
    var royalMailStandardDays: Int?
    var royalMailFirstClassPrice: Double?
    var royalMailFirstClassDays: Int?
    var dpdEnabled: Bool
    var dpdPrice: Double?
    var dpdDays: Int?
    var evriEnabled: Bool
    var evriPrice: Double?
    var evriDays: Int?
    var customOptions: [CustomDeliveryOption]

    static let empty = SellerPostageOptions(
        royalMailEnabled: false,
        royalMailStandardPrice: nil,
        royalMailStandardDays: nil,
        royalMailFirstClassPrice: nil,
        royalMailFirstClassDays: nil,
        dpdEnabled: false,
        dpdPrice: nil,
        dpdDays: nil,
        evriEnabled: false,
        evriPrice: nil,
        evriDays: nil,
        customOptions: []
    )

    /// Build list of delivery options for checkout (name, provider, type, fee). Order: Royal Mail Standard, First Class, DPD.
    func toDeliveryOptions() -> [SellerDeliveryOption] {
        var list: [SellerDeliveryOption] = []
        if royalMailEnabled, let p = royalMailStandardPrice, p >= 0 {
            list.append(SellerDeliveryOption(name: "Royal Mail Standard", deliveryProvider: "ROYAL_MAIL", deliveryType: "HOME_DELIVERY", shippingFee: p, estimatedDays: royalMailStandardDays))
        }
        if royalMailEnabled, let p = royalMailFirstClassPrice, p >= 0 {
            list.append(SellerDeliveryOption(name: "Royal Mail First Class (Next day)", deliveryProvider: "ROYAL_MAIL", deliveryType: "HOME_DELIVERY", shippingFee: p, estimatedDays: royalMailFirstClassDays))
        }
        if dpdEnabled, let p = dpdPrice, p >= 0 {
            list.append(SellerDeliveryOption(name: "DPD Standard", deliveryProvider: "DPD", deliveryType: "HOME_DELIVERY", shippingFee: p, estimatedDays: dpdDays))
        }
        if evriEnabled, let p = evriPrice, p >= 0 {
            list.append(SellerDeliveryOption(name: "Evri Standard", deliveryProvider: "EVRI", deliveryType: "HOME_DELIVERY", shippingFee: p, estimatedDays: evriDays))
        }
        for option in customOptions where option.enabled {
            guard let fee = option.price, fee >= 0 else { continue }
            // Backend supports limited provider enum; map custom carriers to DPD for order creation while preserving display name.
            list.append(SellerDeliveryOption(name: option.name, deliveryProvider: "DPD", deliveryType: "HOME_DELIVERY", shippingFee: fee, estimatedDays: option.deliveryDays))
        }
        return list
    }

    /// From backend meta dict (e.g. meta["postage"]).
    static func from(metaPostage: [String: Any]?) -> SellerPostageOptions? {
        guard let p = metaPostage else { return nil }
        let royalMail = p["royalMail"] as? [String: Any]
        let dpd = p["dpd"] as? [String: Any]
        let evri = p["evri"] as? [String: Any]
        let custom = p["customOptions"] as? [[String: Any]] ?? []
        func num(_ v: Any?) -> Double? {
            if let n = v as? Double { return n }
            if let n = v as? Int { return Double(n) }
            if let s = v as? String { return Double(s) }
            return nil
        }
        func intNum(_ v: Any?) -> Int? {
            if let n = v as? Int { return n }
            if let n = v as? Double { return Int(n) }
            if let s = v as? String { return Int(s) }
            return nil
        }
        let rmEnabled = (royalMail?["enabled"] as? Bool) ?? false
        let dpdEnabled = (dpd?["enabled"] as? Bool) ?? false
        let evriEnabled = (evri?["enabled"] as? Bool) ?? false
        let customOptions: [CustomDeliveryOption] = custom.compactMap { row in
            guard let name = row["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return CustomDeliveryOption(
                id: (row["id"] as? String) ?? UUID().uuidString,
                name: name,
                enabled: (row["enabled"] as? Bool) ?? true,
                price: num(row["price"]),
                deliveryDays: intNum(row["deliveryDays"])
            )
        }
        return SellerPostageOptions(
            royalMailEnabled: rmEnabled,
            royalMailStandardPrice: num(royalMail?["standardPrice"]),
            royalMailStandardDays: intNum(royalMail?["standardDays"]),
            royalMailFirstClassPrice: num(royalMail?["firstClassPrice"]),
            royalMailFirstClassDays: intNum(royalMail?["firstClassDays"]),
            dpdEnabled: dpdEnabled,
            dpdPrice: num(dpd?["standardPrice"]),
            dpdDays: intNum(dpd?["standardDays"]),
            evriEnabled: evriEnabled,
            evriPrice: num(evri?["standardPrice"]),
            evriDays: intNum(evri?["standardDays"]),
            customOptions: customOptions
        )
    }

    /// From decoded GraphQL meta.postage.
    static func from(decoded postage: PostageMetaDecode?) -> SellerPostageOptions? {
        guard let p = postage else { return nil }
        let rm = p.royalMail
        let dpd = p.dpd
        let evri = p.evri
        return SellerPostageOptions(
            royalMailEnabled: rm?.enabled ?? false,
            royalMailStandardPrice: rm?.standardPrice,
            royalMailStandardDays: rm?.standardDays,
            royalMailFirstClassPrice: rm?.firstClassPrice,
            royalMailFirstClassDays: rm?.firstClassDays,
            dpdEnabled: dpd?.enabled ?? false,
            dpdPrice: dpd?.standardPrice,
            dpdDays: dpd?.standardDays,
            evriEnabled: evri?.enabled ?? false,
            evriPrice: evri?.standardPrice,
            evriDays: evri?.standardDays,
            customOptions: p.customOptions?.map {
                CustomDeliveryOption(
                    id: $0.id ?? UUID().uuidString,
                    name: $0.name ?? "Custom delivery",
                    enabled: $0.enabled ?? true,
                    price: $0.price,
                    deliveryDays: $0.deliveryDays
                )
            } ?? []
        )
    }

    /// To meta["postage"] for updateProfile(meta:).
    func toMetaPostage() -> [String: Any] {
        var royalMail: [String: Any] = ["enabled": royalMailEnabled]
        if let p = royalMailStandardPrice { royalMail["standardPrice"] = p }
        if let d = royalMailStandardDays { royalMail["standardDays"] = d }
        if let p = royalMailFirstClassPrice { royalMail["firstClassPrice"] = p }
        if let d = royalMailFirstClassDays { royalMail["firstClassDays"] = d }
        var dpd: [String: Any] = ["enabled": dpdEnabled]
        if let p = dpdPrice { dpd["standardPrice"] = p }
        if let d = dpdDays { dpd["standardDays"] = d }
        var evri: [String: Any] = ["enabled": evriEnabled]
        if let p = evriPrice { evri["standardPrice"] = p }
        if let d = evriDays { evri["standardDays"] = d }
        let custom: [[String: Any]] = customOptions.map {
            var row: [String: Any] = [
                "id": $0.id,
                "name": $0.name,
                "enabled": $0.enabled
            ]
            if let p = $0.price { row["price"] = p }
            if let d = $0.deliveryDays { row["deliveryDays"] = d }
            return row
        }
        return ["royalMail": royalMail, "dpd": dpd, "evri": evri, "customOptions": custom]
    }
}

/// One delivery option at checkout (from seller's postage). Used in PaymentView.
struct SellerDeliveryOption: Hashable {
    let name: String
    let deliveryProvider: String
    let deliveryType: String
    let shippingFee: Double
    let estimatedDays: Int?
}

struct CustomDeliveryOption: Hashable, Identifiable {
    let id: String
    var name: String
    var enabled: Bool
    var price: Double?
    var deliveryDays: Int?
}

struct LocationData: Decodable {
    let locationName: String?
}

/// Decoded meta.postage and meta.payoutBankAccount from viewMe (GraphQL JSON).
struct MetaDecode: Decodable {
    let postage: PostageMetaDecode?
    let payoutBankAccount: PayoutBankAccountDecode?
}

/// Decoded meta.payoutBankAccount (for display on Payments screen).
struct PayoutBankAccountDecode: Decodable {
    let sortCode: String?
    let accountNumber: String?
    let accountHolderName: String?
    let accountLabel: String?
}

/// Display model for active bank account (masked). Built from meta.payoutBankAccount.
struct PayoutBankAccountDisplay: Hashable {
    let maskedSortCode: String
    let maskedAccountNumber: String
    let accountHolderName: String
    let accountLabel: String?

    static func from(decoded d: PayoutBankAccountDecode?) -> PayoutBankAccountDisplay? {
        guard let d = d else { return nil }
        let sortDigits = (d.sortCode ?? "").filter { $0.isNumber }
        let accountDigits = (d.accountNumber ?? "").filter { $0.isNumber }
        guard sortDigits.count == 6, accountDigits.count == 8, !(d.accountHolderName ?? "").trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let last2 = String(sortDigits.suffix(2))
        let last4 = String(accountDigits.suffix(4))
        return PayoutBankAccountDisplay(
            maskedSortCode: "**-**-\(last2)",
            maskedAccountNumber: "****\(last4)",
            accountHolderName: (d.accountHolderName ?? "").trimmingCharacters(in: .whitespaces),
            accountLabel: (d.accountLabel ?? "").trimmingCharacters(in: .whitespaces).isEmpty ? nil : d.accountLabel?.trimmingCharacters(in: .whitespaces)
        )
    }
}

/// Decodes backend `meta` whether it comes as a JSON object or a JSON string (GraphQL JSONString can be either). Used by UserService and ProductService.
struct SafeMetaDecode: Decodable {
    var value: MetaDecode?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
            return
        }
        if let m = try? container.decode(MetaDecode.self) {
            value = m
            return
        }
        if let s = try? container.decode(String.self), let data = s.data(using: .utf8), let m = try? JSONDecoder().decode(MetaDecode.self, from: data) {
            value = m
        } else {
            value = nil
        }
    }
}

struct PostageMetaDecode: Decodable {
    let royalMail: RoyalMailMetaDecode?
    let dpd: DpdMetaDecode?
    let evri: DpdMetaDecode?
    let customOptions: [CustomOptionMetaDecode]?
}
struct RoyalMailMetaDecode: Decodable {
    let enabled: Bool?
    let standardPrice: Double?
    let standardDays: Int?
    let firstClassPrice: Double?
    let firstClassDays: Int?
}
struct DpdMetaDecode: Decodable {
    let enabled: Bool?
    let standardPrice: Double?
    let standardDays: Int?
}
struct CustomOptionMetaDecode: Decodable {
    let id: String?
    let name: String?
    let enabled: Bool?
    let price: Double?
    let deliveryDays: Int?
}

struct ReviewStatsData: Decodable {
    let noOfReviews: Int?
    let rating: Double?
}

// Helper to decode Any type (for id which can be String or Int)
// Made public so it can be used in other services
public struct AnyCodable: Decodable {
    public let value: Any
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
        }
    }
}

/// Decodes GraphQL Decimal as either String or number.
private struct DecimalStringOrNumber: Decodable {
    let stringValue: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            stringValue = s
        } else if let n = try? c.decode(Double.self) {
            stringValue = String(Int(n))
        } else if let n = try? c.decode(Int.self) {
            stringValue = String(n)
        } else {
            throw DecodingError.typeMismatch(DecimalStringOrNumber.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or number for Decimal"))
        }
    }
}

struct UserProductsResponse: Decodable {
    let userProducts: [ProductData]?
}

struct MyReportRow: Decodable, Identifiable {
    let id: Int
    let publicId: String?
    let reportType: String?
    let reason: String?
    let context: String?
    let imagesUrl: [String]?
    let status: String?
    let dateCreated: String?
    let updatedAt: String?
    let accountReportedUsername: String?
    let productId: Int?
    let productName: String?
    let supportConversationId: Int?
}

struct UserEarnings {
    let networth: Double
    let pendingPayments: QuantityValue
    let completedPayments: QuantityValue
    let earningsInMonth: QuantityValue
    let totalEarnings: QuantityValue
}

struct QuantityValue {
    let quantity: Int
    let value: Double
}

struct UserEarningsResponse: Decodable {
    let userEarnings: UserEarningsData?
}

struct UserEarningsData: Decodable {
    let networth: Double?
    let pendingPayments: QuantityValueData?
    let completedPayments: QuantityValueData?
    let earningsInMonth: QuantityValueData?
    let totalEarnings: QuantityValueData?
}

struct QuantityValueData: Decodable {
    let quantity: Int?
    let value: Double?
}

struct UpdateProfileResponse: Decodable {
    let updateProfile: UpdateProfilePayload?
}

struct UpdateProfilePayload: Decodable {
    let message: String?
}

struct SendDebugTestPushResponse: Decodable {
    let sendDebugTestPush: SendDebugTestPushPayload?
}

struct SendDebugTestPushPayload: Decodable {
    let success: Bool?
    let message: String?
}

struct ChangeEmailResponse: Decodable {
    let changeEmail: ChangeEmailPayload?
}

struct ChangeEmailPayload: Decodable {
    let message: String?
}

struct SendSmsOtpResponse: Decodable {
    let sendSmsOtp: SendSmsOtpPayload?
}

struct SendSmsOtpPayload: Decodable {
    let success: Bool?
    let message: String?
}

/// One multi-buy discount tier (minItems → discount %). Matches MultibuyDiscountType.
struct MultibuyDiscount {
    let id: Int?
    let minItems: Int
    let discountValue: String
    let isActive: Bool
}

/// Input for createMultibuyDiscount mutation. id = nil for create, non-nil for update.
struct MultibuyDiscountInput {
    let id: Int?
    let minItems: Int
    let discountPercentage: String
    let isActive: Bool
}

struct RaiseOrderIssueResult: Decodable {
    let success: Bool?
    let message: String?
    let issueId: Int?
    let publicId: String?
    /// Buyer ↔ support system thread (persisted); use with Help Chat / admin replies.
    let supportConversationId: Int?
}

struct SubmittedReportRef {
    let reportId: Int?
    let publicId: String?
    let supportConversationId: Int?
}

struct OrderIssueDetails: Decodable, Identifiable {
    /// GraphQL `OrderType.id` is an integer; keep as string for display consistency with the rest of the app.
    struct OrderRef: Decodable {
        let id: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let s = try? c.decode(String.self, forKey: .id) {
                id = s
            } else if let i = try? c.decode(Int.self, forKey: .id) {
                id = String(i)
            } else {
                id = nil
            }
        }

        private enum CodingKeys: String, CodingKey { case id }
    }

    struct RaisedByRef: Decodable { let username: String? }

    let id: Int
    let publicId: String?
    let issueType: String
    let description: String
    let imagesUrl: [String]
    let otherIssueDescription: String?
    let status: String?
    /// Backend sends ISO8601 strings; `GraphQLClient` does not set `dateDecodingStrategy`, so keep as `String`.
    let createdAt: String?
    let order: OrderRef?
    let raisedBy: RaisedByRef?

    private enum CodingKeys: String, CodingKey {
        case id, publicId, issueType, description, imagesUrl, otherIssueDescription, status, createdAt, order, raisedBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = intId
        } else if let strId = try? c.decode(String.self, forKey: .id), let intId = Int(strId) {
            id = intId
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Expected numeric issue id")
        }
        publicId = try c.decodeIfPresent(String.self, forKey: .publicId)
        issueType = try c.decodeIfPresent(String.self, forKey: .issueType) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        if let urls = try? c.decode([String].self, forKey: .imagesUrl) {
            imagesUrl = urls
        } else {
            imagesUrl = []
        }
        otherIssueDescription = try c.decodeIfPresent(String.self, forKey: .otherIssueDescription)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        order = try c.decodeIfPresent(OrderRef.self, forKey: .order)
        raisedBy = try c.decodeIfPresent(RaisedByRef.self, forKey: .raisedBy)
    }
}

/// Pending / resolved cancellation from GraphQL `cancelledOrder` on an order.
struct OrderCancellationSummary: Equatable, Sendable {
    let status: String
    let requestedBySeller: Bool
}

/// Order from userOrders query. Used in My Orders list and detail.
struct Order: Identifiable {
    let id: String
    let publicId: String?
    let priceTotal: String
    /// Total merchandise discount on the order (e.g. multi-buy); monetary amount from API.
    let discountPrice: String?
    let status: String
    let createdAt: Date
    let otherParty: User?
    let products: [OrderProductSummary]
    let shippingAddress: ShippingAddress?
    let shipmentService: String?
    let deliveryDate: Date?
    let trackingNumber: String?
    let trackingUrl: String?
    let buyerOrderCountWithSeller: Int?
    /// When present, buyer/seller cancellation request flow (PENDING needs counterparty action).
    let cancellation: OrderCancellationSummary?

    /// Order ID for display: prefers backend `publicId` (e.g. PR23DG2DF3). Falls back when navigating from chat before hydration.
    var displayOrderId: String {
        let trimmed = publicId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        let nid = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return nid.isEmpty ? "—" : "#\(nid)"
    }
}

/// Product summary inside an order.
struct OrderProductSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let imageUrl: String?
    let price: String?
    let condition: String?
    let colors: [String]
    let style: String?
    let size: String?
    let brand: String?
    let materials: [String]
}

/// Payment method from userPaymentMethods query.
struct PaymentMethod {
    let paymentMethodId: String
    let last4Digits: String
    let cardBrand: String
}

/// Blocked user from blockedUsers query.
struct BlockedUser: Identifiable {
    let id: Int
    let username: String
    let displayName: String
    let profilePictureUrl: String?
    let thumbnailUrl: String?
}

struct BlockedUsersResponse: Decodable {
    let blockedUsers: [BlockedUserRow]?
    let blockedUsersTotalNumber: Int?
}

struct BlockedUserRow: Decodable {
    let id: Int?
    let username: String?
    let displayName: String?
    let profilePictureUrl: String?
    let thumbnailUrl: String?
}

/// One entry from recommendedSellers query (Top Shops).
struct RecommendedSeller {
    let seller: User
    let totalSales: String?
    let totalShopValue: String?
    let productViews: Int
    let sellerScore: Double
    let activeListings: Int
}

// Reuse ProductData, SizeData, BrandData, SellerData, CategoryData from ProductService
// These are defined in ProductService.swift

enum UserError: Error, LocalizedError {
    case userNotFound
    case backendMessage(String)
    
    var errorDescription: String? {
        switch self {
        case .userNotFound:
            return "User not found"
        case .backendMessage(let message):
            return message
        }
    }
}
