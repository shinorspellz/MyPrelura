import Foundation

final class GraphQLClient: @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private var authToken: String?

    init(baseURL: String = Constants.graphQLBaseURL) {
        self.baseURL = URL(string: baseURL)!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.apiTimeout
        config.timeoutIntervalForResource = Constants.apiTimeout
        self.session = URLSession(configuration: config)
    }

    func setAuthToken(_ token: String?) {
        authToken = token
    }

    func execute<T: Decodable>(
        query: String,
        variables: [String: Any]? = nil,
        responseType: T.Type
    ) async throws -> T {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var body: [String: Any] = ["query": query]
        if let variables { body["variables"] = variables }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GraphQLError.networkError("Invalid response")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let graphQLResponse: GraphQLResponse<T>
        do {
            graphQLResponse = try decoder.decode(GraphQLResponse<T>.self, from: data)
        } catch {
            if !(200...299).contains(http.statusCode) { throw GraphQLError.httpError(http.statusCode) }
            throw GraphQLError.decodingError(error)
        }

        if let errors = graphQLResponse.errors, !errors.isEmpty {
            throw GraphQLError.graphQLErrors(errors)
        }
        if !(200...299).contains(http.statusCode) {
            throw GraphQLError.httpError(http.statusCode)
        }
        guard let responseData = graphQLResponse.data else {
            throw GraphQLError.noData
        }
        return responseData
    }
}

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLErrorResponse]?
}

struct GraphQLErrorResponse: Decodable {
    let message: String
}

enum GraphQLError: Error, LocalizedError {
    case networkError(String)
    case httpError(Int)
    case graphQLErrors([GraphQLErrorResponse])
    case noData
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .networkError(let s): return s
        case .httpError(let c): return "HTTP \(c)"
        case .graphQLErrors(let e): return e.first?.message ?? "GraphQL error"
        case .noData: return "No data"
        case .decodingError(let e): return "Decode: \(e.localizedDescription)"
        }
    }
}
