import Foundation

/// Response wrapper of `GET /liveclientdata/eventdata`.
public struct LiveEventsResponse: Decodable, Equatable, Sendable {
    public let events: [LiveGameEvent]

    private enum CodingKeys: String, CodingKey {
        case events = "Events"
    }

    public init(events: [LiveGameEvent]) {
        self.events = events
    }
}

/// One event from `GET /liveclientdata/eventdata`.
public struct LiveGameEvent: Decodable, Equatable, Sendable {
    public let eventID: Int
    public let eventName: String
    public let eventTime: Double
    public let dragonType: String?
    public let inhibKilled: String?
    public let inhibRespawned: String?

    private enum CodingKeys: String, CodingKey {
        case eventID = "EventID"
        case eventName = "EventName"
        case eventTime = "EventTime"
        case dragonType = "DragonType"
        case inhibKilled = "InhibKilled"
        case inhibRespawned = "InhibRespawned"
    }

    public init(
        eventID: Int,
        eventName: String,
        eventTime: Double,
        dragonType: String? = nil,
        inhibKilled: String? = nil,
        inhibRespawned: String? = nil
    ) {
        self.eventID = eventID
        self.eventName = eventName
        self.eventTime = eventTime
        self.dragonType = dragonType
        self.inhibKilled = inhibKilled
        self.inhibRespawned = inhibRespawned
    }
}

/// Respawn timer derived from objective events visible to all players in game.
public struct ObjectiveTimer: Equatable, Identifiable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case dragon
        case elder
        case baron
        case inhibitor
    }

    public let id: String
    public let kind: Kind
    public let label: String
    public let respawnTime: Double

    public init(id: String, kind: Kind, label: String, respawnTime: Double) {
        self.id = id
        self.kind = kind
        self.label = label
        self.respawnTime = respawnTime
    }

    public func remainingSeconds(at gameTime: Double) -> Int {
        max(0, Int(ceil(respawnTime - gameTime)))
    }

    public func formattedRemaining(at gameTime: Double) -> String {
        let remaining = remainingSeconds(at: gameTime)
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }
}

/// Computes active respawn countdowns from neutral objective / inhibitor kill events.
public enum ObjectiveTimerTracker {
    public static func activeTimers(from events: [LiveGameEvent], at gameTime: Double) -> [ObjectiveTimer] {
        var timers: [String: ObjectiveTimer] = [:]
        for event in events.sorted(by: { $0.eventTime < $1.eventTime }) {
            switch event.eventName {
            case "DragonKill":
                let isElder = event.dragonType?.caseInsensitiveCompare("Elder") == .orderedSame
                timers["dragon"] = ObjectiveTimer(
                    id: "dragon",
                    kind: isElder ? .elder : .dragon,
                    label: isElder ? "Elder" : "Dragon",
                    respawnTime: event.eventTime + (isElder ? 360 : 300)
                )
            case "BaronKill":
                timers["baron"] = ObjectiveTimer(
                    id: "baron",
                    kind: .baron,
                    label: "Baron",
                    respawnTime: event.eventTime + 360
                )
            case "InhibKilled":
                guard let inhib = event.inhibKilled, !inhib.isEmpty else { continue }
                let key = "inhib-\(inhib)"
                timers[key] = ObjectiveTimer(
                    id: key,
                    kind: .inhibitor,
                    label: inhibitorLabel(inhib),
                    respawnTime: event.eventTime + 300
                )
            case "InhibRespawned":
                if let inhib = event.inhibRespawned {
                    timers.removeValue(forKey: "inhib-\(inhib)")
                }
            default:
                break
            }
        }
        return timers.values.filter { $0.respawnTime > gameTime }.sorted { $0.respawnTime < $1.respawnTime }
    }

    private static func inhibitorLabel(_ raw: String) -> String {
        let side = raw.contains("T1") ? "Blue" : raw.contains("T2") ? "Red" : nil
        let lane = raw.contains("_L") ? "Top" : raw.contains("_C") ? "Mid" : raw.contains("_R") ? "Bot" : nil
        let parts = [side, lane].compactMap(\.self)
        return parts.isEmpty ? "Inhibitor" : parts.joined(separator: " ") + " Inhib"
    }
}
