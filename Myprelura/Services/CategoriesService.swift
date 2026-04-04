import Foundation

/// Fetches hierarchical categories from the same GraphQL API as Flutter (categories(parentId)).
final class CategoriesService {
    private let client: GraphQLClient

    init(client: GraphQLClient = GraphQLClient()) {
        self.client = client
    }

    private static let categoriesQuery = """
    query Categories($parentId: Int) {
      categories(parentId: $parentId) {
        id
        name
        hasChildren
        fullPath
      }
    }
    """

    struct CategoriesResponse: Decodable {
        let categories: [APICategory]?
    }

    /// Fetch categories for a parent. Pass nil for root (Men, Women, Boys, Girls, Toddlers, etc.).
    func fetchCategories(parentId: Int?) async throws -> [APICategory] {
        var variables: [String: Any] = [:]
        if let id = parentId {
            variables["parentId"] = id
        }
        let body = try await client.execute(
            query: Self.categoriesQuery,
            variables: variables.isEmpty ? nil : variables,
            operationName: "Categories",
            responseType: CategoriesResponse.self
        )
        return body.categories ?? []
    }

    /// Recursively fetch all categories and return leaf categories with full path (for search). Fetches root children in parallel for speed.
    func fetchAllCategoriesFlattened() async throws -> [CategoryPathEntry] {
        let root = try await fetchCategories(parentId: nil)
        return await withTaskGroup(of: [CategoryPathEntry].self, returning: [CategoryPathEntry].self) { group in
            for cat in root {
                group.addTask {
                    (try? await self.collectLeaves(category: cat, pathNames: [cat.name], pathIds: [cat.id])) ?? []
                }
            }
            var result: [CategoryPathEntry] = []
            for await chunk in group {
                result.append(contentsOf: chunk)
            }
            return result
        }
    }

    private func collectLeaves(category: APICategory, pathNames: [String], pathIds: [String]) async throws -> [CategoryPathEntry] {
        if category.hasChildren != true {
            return [CategoryPathEntry(id: category.id, name: category.name, pathNames: pathNames, pathIds: pathIds)]
        }
        let children = try await fetchCategories(parentId: Int(category.id))
        return await withTaskGroup(of: [CategoryPathEntry].self, returning: [CategoryPathEntry].self) { group in
            for child in children {
                group.addTask {
                    (try? await self.collectLeaves(category: child, pathNames: pathNames + [child.name], pathIds: pathIds + [child.id])) ?? []
                }
            }
            var result: [CategoryPathEntry] = []
            for await chunk in group {
                result.append(contentsOf: chunk)
            }
            return result
        }
    }
}
