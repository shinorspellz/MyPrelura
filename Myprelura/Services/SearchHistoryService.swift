import Foundation
import Combine

/// Search history (user's recent + recommended/trending). Matches Flutter SearchHistoryRepo. Requires auth for user history and delete.
@MainActor
class SearchHistoryService: ObservableObject {
    private var client: GraphQLClient
    /// Keeps ObservableObject conformance for @StateObject in views.
    @Published private(set) var placeholder = 0

    init(client: GraphQLClient? = nil) {
        self.client = client ?? GraphQLClient()
        if let token = UserDefaults.standard.string(forKey: "AUTH_TOKEN") {
            self.client.setAuthToken(token)
        }
    }

    func updateAuthToken(_ token: String?) {
        client.setAuthToken(token)
    }

    /// User's own search history. Auth required. searchType: "PRODUCT" or "USER".
    func getUserSearchHistory(searchType: String = "PRODUCT", pageNumber: Int = 1, pageCount: Int = 20) async throws -> [SearchHistoryItem] {
        let query = """
        query UserSearchHistory($searchType: SearchTypeEnum, $pageCount: Int, $pageNumber: Int) {
          userSearchHistory(searchType: $searchType, pageCount: $pageCount, pageNumber: $pageNumber) {
            id
            query
            timestamp
            searchType
            searchCount
            lastSearched
          }
        }
        """
        let variables: [String: Any] = [
            "searchType": searchType,
            "pageNumber": pageNumber,
            "pageCount": pageCount
        ]
        struct Payload: Decodable {
            let userSearchHistory: [SearchHistoryItemPayload]?
        }
        struct SearchHistoryItemPayload: Decodable {
            let id: String?
            let query: String?
            let timestamp: String?
            let searchType: String?
            let searchCount: Int?
            let lastSearched: String?
        }
        let response: Payload = try await client.execute(query: query, variables: variables, responseType: Payload.self)
        return (response.userSearchHistory ?? []).map { item in
            SearchHistoryItem(
                id: item.id ?? "",
                query: item.query ?? "",
                timestamp: parseISO8601(item.timestamp),
                searchType: item.searchType,
                searchCount: item.searchCount ?? 0,
                lastSearched: parseISO8601(item.lastSearched)
            )
        }
    }

    /// Recommended/trending search history. searchType: "PRODUCT" or "USER" (required).
    func getRecommendedSearchHistory(searchType: String = "PRODUCT", pageNumber: Int = 1, pageCount: Int = 20) async throws -> [SearchHistoryItem] {
        let query = """
        query RecommendedSearchHistory($searchType: SearchTypeEnum!, $pageCount: Int, $pageNumber: Int) {
          recommendedSearchHistory(searchType: $searchType, pageCount: $pageCount, pageNumber: $pageNumber) {
            id
            query
            timestamp
            searchType
            searchCount
            lastSearched
          }
        }
        """
        let variables: [String: Any] = [
            "searchType": searchType,
            "pageNumber": pageNumber,
            "pageCount": pageCount
        ]
        struct Payload: Decodable {
            let recommendedSearchHistory: [SearchHistoryItemPayload]?
        }
        struct SearchHistoryItemPayload: Decodable {
            let id: String?
            let query: String?
            let timestamp: String?
            let searchType: String?
            let searchCount: Int?
            let lastSearched: String?
        }
        let response: Payload = try await client.execute(query: query, variables: variables, responseType: Payload.self)
        return (response.recommendedSearchHistory ?? []).map { item in
            SearchHistoryItem(
                id: item.id ?? "",
                query: item.query ?? "",
                timestamp: parseISO8601(item.timestamp),
                searchType: item.searchType,
                searchCount: item.searchCount ?? 0,
                lastSearched: parseISO8601(item.lastSearched)
            )
        }
    }

    /// Delete one search history entry or clear all. Auth required.
    func deleteSearchHistory(searchId: String?, clearAll: Bool?) async throws -> Bool {
        var variables: [String: Any] = [:]
        if let id = searchId { variables["searchId"] = id }
        if let all = clearAll { variables["clearAll"] = all }
        let mutation = """
        mutation DeleteSearchHistory($searchId: ID, $clearAll: Boolean) {
          deleteSearchHistory(searchId: $searchId, clearAll: $clearAll) {
            success
            message
          }
        }
        """
        struct Payload: Decodable {
            let deleteSearchHistory: Result?
            struct Result: Decodable {
                let success: Bool?
                let message: String?
            }
        }
        let response: Payload = try await client.execute(query: mutation, variables: variables.isEmpty ? nil : variables, responseType: Payload.self)
        return response.deleteSearchHistory?.success ?? false
    }

    private func parseISO8601(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

struct SearchHistoryItem: Identifiable, Hashable {
    let id: String
    let query: String
    let timestamp: Date?
    let searchType: String?
    let searchCount: Int
    let lastSearched: Date?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: SearchHistoryItem, rhs: SearchHistoryItem) -> Bool { lhs.id == rhs.id }
}
