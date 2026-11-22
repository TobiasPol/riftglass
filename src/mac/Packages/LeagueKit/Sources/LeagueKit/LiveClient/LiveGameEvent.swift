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
    public let killerName: String?
    public let dragonType: String?
    public let inhibKilled: String?
    public let inhibRespawned: String?

    private enum CodingKeys: String, CodingKey {
        case eventID = "EventID"
        case eventName = "EventName"
        case eventTime = "EventTime"
        case killerName = "KillerName"
        case dragonType = "DragonType"
        case inhibKilled = "InhibKilled"
        case inhibRespawned = "InhibRespawned"
    }

    public init(
        eventID: Int,
        eventName: String,
        eventTime: Double,
        killerName: String? = nil,
        dragonType: String? = nil,
        inhibKilled: String? = nil,
        inhibRespawned: String? = nil
    ) {
        self.eventID = eventID
        self.eventName = eventName
        self.eventTime = eventTime
        self.killerName = killerName
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
    private struct DrakeState {
        var teamDrakes: [String: Int] = [:]
        var totalElemental = 0
        var elderNext = false

        mutating func recordKill(_ event: LiveGameEvent, teams: [String: String]) -> ObjectiveTimer {
            if event.dragonType?.caseInsensitiveCompare("Elder") == .orderedSame {
                elderNext = true
            } else if !elderNext {
                totalElemental += 1
                if let team = event.killerName.flatMap({ teams[$0] }) {
                    let count = teamDrakes[team, default: 0] + 1
                    teamDrakes[team] = count
                    if count >= 4 {
                        elderNext = true
                    }
                } else if totalElemental >= 7 {
                    elderNext = true
                }
            }
            return ObjectiveTimer(
                id: "dragon",
                kind: elderNext ? .elder : .dragon,
                label: elderNext ? "Elder" : "Dragon",
                respawnTime: event.eventTime + (elderNext ? 360 : 300)
            )
        }
    }

    public static func activeTimers(
        from events: [LiveGameEvent],
        players: [LivePlayer] = [],
        at gameTime: Double
    ) -> [ObjectiveTimer] {
        let teams = teamByName(from: players)
        var timers: [String: ObjectiveTimer] = [:]
        var drakes = DrakeState()
        for event in events.sorted(by: { $0.eventTime < $1.eventTime }) {
            switch event.eventName {
            case "DragonKill":
                timers["dragon"] = drakes.recordKill(event, teams: teams)
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

    private static func teamByName(from players: [LivePlayer]) -> [String: String] {
        var fullIds: [String: String] = [:]
        var shortNames: [String: Set<String>] = [:]
        for player in players {
            if let riotId = player.riotId, !riotId.isEmpty {
                fullIds[riotId] = player.team
            }
            for alias in [player.riotIdGameName, player.summonerName].compactMap(\.self) where !alias.isEmpty {
                shortNames[alias, default: []].insert(player.team)
            }
        }
        var result: [String: String] = [:]
        for (alias, teams) in shortNames where teams.count == 1 {
            if let team = teams.first {
                result[alias] = team
            }
        }
        for (riotId, team) in fullIds {
            result[riotId] = team
        }
        return result
    }

    private static func inhibitorLabel(_ raw: String) -> String {
        let side = raw.contains("T1") ? "Blue" : raw.contains("T2") ? "Red" : nil
        let lane = raw.contains("_L") ? "Top" : raw.contains("_C") ? "Mid" : raw.contains("_R") ? "Bot" : nil
        let parts = [side, lane].compactMap(\.self)
        return parts.isEmpty ? "Inhibitor" : parts.joined(separator: " ") + " Inhib"
    }
}
