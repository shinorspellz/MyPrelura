import Foundation

/// Fetches materials from the same GraphQL API as Flutter (materials(pageCount, pageNumber, search)).
/// Backend returns [BrandType] with id and name.
final class MaterialsService {
    private let client: GraphQLClient

    init(client: GraphQLClient = GraphQLClient()) {
        self.client = client
    }

    func setAuthToken(_ token: String?) {
        client.setAuthToken(token)
    }

    private static let materialsQuery = """
    query Materials($pageCount: Int, $pageNumber: Int, $search: String) {
      materials(pageCount: $pageCount, pageNumber: $pageNumber, search: $search) {
        id
        name
      }
    }
    """

    struct MaterialsResponse: Decodable {
        let materials: [APIMaterial]?
    }

    /// Fetch materials for the sell form. Uses same API as Flutter getMaterial.
    func fetchMaterials(pageCount: Int = 100, pageNumber: Int = 1, search: String? = nil) async throws -> [APIMaterial] {
        var variables: [String: Any] = [
            "pageCount": pageCount,
            "pageNumber": pageNumber
        ]
        if let q = search?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            variables["search"] = q
        }
        let body = try await client.execute(
            query: Self.materialsQuery,
            variables: variables,
            operationName: "Materials",
            responseType: MaterialsResponse.self
        )
        return body.materials ?? []
    }

    /// Resolve material name to backend material id (for CreateProduct). Fetches one page and finds first match by name.
    func getMaterialId(byName name: String) async throws -> Int? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let list = try await fetchMaterials(pageCount: 100, search: trimmed)
        return list.first { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased() }?.id
    }
}
