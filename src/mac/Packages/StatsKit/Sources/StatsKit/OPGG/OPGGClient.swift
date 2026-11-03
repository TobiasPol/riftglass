import Foundation

/// Abstraction over HTTP POST so the OP.GG client can be tested offline.
public protocol HTTPPosting: Sendable {
    func post(_ url: URL, body: Data, headers: [String: String]) async throws -> Data
}

public struct URLSessionPoster: HTTPPosting {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func post(_ url: URL, body: Data, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = body
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw OPGGError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }
}

public enum OPGGError: Error, Equatable {
    case http(Int)
    case rpc(String)
    case toolError(String)
    case emptyResponse
}

/// Minimal client for OP.GG's official public MCP server (`https://mcp-api.op.gg/mcp`).
/// `tools/call` works statelessly, without an `initialize` handshake (docs/SPIKE.md).
public struct OPGGClient: Sendable {
    public static let endpoint = URL(string: "https://mcp-api.op.gg/mcp")!

    private let poster: any HTTPPosting
    private let userAgent: String

    public init(poster: any HTTPPosting = URLSessionPoster(), userAgent: String = "Riftglass") {
        self.poster = poster
        self.userAgent = userAgent
    }

    /// Calls a tool and returns its text output (OP.GG's class notation).
    public func callTool(_ name: String, arguments: [String: ToolArgument]) async throws -> String {
        let request = RPCRequest(params: .init(name: name, arguments: arguments))
        let body = try JSONEncoder().encode(request)
        let headers = [
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "User-Agent": userAgent
        ]
        let data = try await poster.post(Self.endpoint, body: body, headers: headers)
        return try Self.text(fromResponse: data)
    }

    static func text(fromResponse data: Data) throws -> String {
        let json = Self.jsonPayload(data)
        let response = try JSONDecoder().decode(RPCResponse.self, from: json)
        if let error = response.error {
            throw OPGGError.rpc(error.message)
        }
        guard let text = response.result?.content.first(where: { $0.type == "text" })?.text else {
            throw OPGGError.emptyResponse
        }
        if response.result?.isError == true {
            throw OPGGError.toolError(text)
        }
        return text
    }

    /// The server may answer as Server-Sent Events; then the JSON is in the `data:` line.
    private static func jsonPayload(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8), !text.hasPrefix("{") else { return data }
        let line = text.split(separator: "\n").last { $0.hasPrefix("data:") }
        return line.map { Data($0.dropFirst(5).utf8) } ?? data
    }
}

public enum ToolArgument: Encodable, Equatable, Sendable {
    case string(String)
    case strings([String])
    case int(Int)

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .strings(values): try container.encode(values)
        case let .int(value): try container.encode(value)
        }
    }
}

private struct RPCRequest: Encodable {
    struct Params: Encodable {
        let name: String
        let arguments: [String: ToolArgument]
    }

    var jsonrpc = "2.0"
    var id = 1
    var method = "tools/call"
    let params: Params
}

private struct RPCContent: Decodable {
    let type: String
    let text: String?
}

private struct RPCResponse: Decodable {
    struct Result: Decodable {
        let content: [RPCContent]
        let isError: Bool?
    }

    struct RPCError: Decodable {
        let message: String
    }

    let result: Result?
    let error: RPCError?
}
