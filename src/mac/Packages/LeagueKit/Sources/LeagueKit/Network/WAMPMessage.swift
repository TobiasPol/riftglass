import Foundation

/// Messages of the LCU's WAMP 1.0 dialect.
///
/// The client greets with `[0, session, 1, "WAMP-1.0-RiotRemoting"]`; only then are subscriptions
/// (`[5, topic]`) honoured. Specific topics deliver nothing on macOS (docs/SPIKE.md), so Riftglass
/// subscribes to `OnJsonApiEvent` and filters events by URI.
public enum WAMPMessage: Equatable, Sendable {
    case welcome(session: String)
    case event(LCUEvent)

    public static let catchAllTopic = "OnJsonApiEvent"

    public static func subscribe(_ topic: String = catchAllTopic) -> String {
        "[5,\"\(topic)\"]"
    }

    /// Parses a frame. Events whose URI is not in `uris` are dropped **before** JSON decoding –
    /// the catch-all topic delivers many events Riftglass does not care about.
    public static func parse(_ data: Data, keeping uris: Set<String>) -> WAMPMessage? {
        guard let opcode = data.dropFirst().first else { return nil }
        switch opcode {
        case UInt8(ascii: "0"):
            return parseWelcome(data)
        case UInt8(ascii: "8"):
            guard uris.contains(where: { data.range(of: Data("\"uri\":\"\($0)\"".utf8)) != nil }) else {
                return nil
            }
            return parseEvent(data, keeping: uris)
        default:
            return nil
        }
    }

    private static func parseWelcome(_ data: Data) -> WAMPMessage? {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              array.count >= 2, let session = array[1] as? String
        else { return nil }
        return .welcome(session: session)
    }

    private static func parseEvent(_ data: Data, keeping uris: Set<String>) -> WAMPMessage? {
        guard let frame = try? LCUCoding.decoder.decode(EventFrame.self, from: data),
              uris.contains(frame.payload.uri)
        else { return nil }
        return .event(frame.payload)
    }
}

/// An LCU JSON API event: `{ "data": …, "eventType": "Create|Update|Delete", "uri": … }`.
public struct LCUEvent: Decodable, Equatable, Sendable {
    public enum Kind: String, Decodable, Sendable { case create = "Create", update = "Update", delete = "Delete" }

    public let uri: String
    public let eventType: Kind
    /// Raw JSON of `data`, decoded lazily by the consumer.
    public let data: JSONValue

    public func decode<T: Decodable>(_: T.Type) throws -> T {
        try LCUCoding.decoder.decode(T.self, from: LCUCoding.encoder.encode(data))
    }
}

/// `[8, topic, payload]` – decoded positionally.
private struct EventFrame: Decodable {
    let payload: LCUEvent

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        _ = try container.decode(Int.self)
        _ = try container.decode(String.self)
        payload = try container.decode(LCUEvent.self)
    }
}
