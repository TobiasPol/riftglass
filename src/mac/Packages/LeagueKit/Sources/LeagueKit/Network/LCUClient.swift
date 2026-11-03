import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
}

public enum LCUError: Error, Equatable {
    case http(status: Int, path: String)
    case invalidPath(String)
}

/// Anything that can send a request to the LCU. Lets the import logic run against fakes in tests.
public protocol LCURequesting: Sendable {
    func data(_ method: HTTPMethod, _ path: String, body: Data?) async throws -> Data
}

public extension LCURequesting {
    func get<T: Decodable>(_ path: String, as _: T.Type = T.self) async throws -> T {
        let raw = try await data(.get, path, body: nil)
        return try LCUCoding.decoder.decode(T.self, from: raw)
    }

    @discardableResult
    func send(_ method: HTTPMethod, _ path: String, json body: some Encodable) async throws -> Data {
        try await data(method, path, body: LCUCoding.encoder.encode(body))
    }

    @discardableResult
    func send(_ method: HTTPMethod, _ path: String) async throws -> Data {
        try await data(method, path, body: nil)
    }
}

enum LCUCoding {
    static let decoder = JSONDecoder()
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

/// REST client for the League Client Update (LCU) API on `https://127.0.0.1:<port>`.
public actor LCUClient: LCURequesting {
    public let credentials: LCUCredentials
    private let session: URLSession

    public init(credentials: LCUCredentials, evaluator: LocalTrustEvaluator) {
        self.credentials = credentials
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.httpMaximumConnectionsPerHost = 4
        let delegate = LocalTrustDelegate(evaluator: evaluator, ports: [credentials.port])
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    public func data(_ method: HTTPMethod, _ path: String, body: Data?) async throws -> Data {
        let request = try makeRequest(method, path, body: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else { throw LCUError.http(status: status, path: path) }
        return data
    }

    nonisolated func makeRequest(_ method: HTTPMethod, _ path: String, body: Data?) throws -> URLRequest {
        guard path.hasPrefix("/"),
              let url = URL(string: "https://\(LocalTrustEvaluator.allowedHost):\(credentials.port)\(path)")
        else { throw LCUError.invalidPath(path) }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(credentials.basicAuthorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
