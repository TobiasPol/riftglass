import Foundation

/// Reads the augment tier list out of OP.GG's ARAM: Mayhem champion page
/// (`op.gg/lol/modes/aram-mayhem/<champion>/augments`).
///
/// The page is a Next.js app: its data arrives as "flight" chunks, each a JS string literal inside
/// `<script>self.__next_f.push([1,"…"])</script>`. Joined, they contain the augment list as plain JSON:
/// `{"data":[{"id":1214,"tier":0,"performance":78.54,"popular":3.46,"name":"Spin To Win","rarity":1,…},…]}`
/// (docs/SPIKE.md). The array is found by its shape, not by its position in the page.
enum OPGGAugmentPage {
    static func augments(fromHTML html: Data) throws -> [AugmentStat] {
        let payload = flightPayload(fromHTML: html)
        guard let entries = augmentEntries(in: payload) else { throw OPGGError.unexpectedPage }
        let stats = entries.compactMap(\.stat).sorted(by: AugmentStat.tierListOrder)
        guard !stats.isEmpty else { throw OPGGError.unexpectedPage }
        return stats
    }

    /// All flight chunks of the page, decoded and joined – one row can span several chunks.
    static func flightPayload(fromHTML html: Data) -> Data {
        let marker = Data("self.__next_f.push([1,".utf8)
        let terminator = Data("])</script>".utf8)
        var payload = Data()
        var cursor = html.startIndex
        while let start = html.range(of: marker, in: cursor ..< html.endIndex),
              let end = html.range(of: terminator, in: start.upperBound ..< html.endIndex) {
            // `"…"` is a valid JSON string (Next escapes `<`, so `</script>` cannot occur inside).
            var literal = Data("[".utf8)
            literal.append(html[start.upperBound ..< end.lowerBound])
            literal.append(Data("]".utf8))
            if let chunk = try? JSONDecoder().decode([String].self, from: literal).first {
                payload.append(Data(chunk.utf8))
            }
            cursor = end.upperBound
        }
        return payload
    }

    /// The first JSON array of objects that decodes as augments (ID, tier and popularity present).
    /// Other `[{"id":…}]` arrays of the page (champions, items) lack those fields and are skipped.
    static func augmentEntries(in payload: Data) -> [Entry]? {
        let opening = Data(#"[{"id":"#.utf8)
        var cursor = payload.startIndex
        while let start = payload.range(of: opening, in: cursor ..< payload.endIndex) {
            if let end = endOfArray(in: payload, from: start.lowerBound),
               let entries = try? JSONDecoder().decode([Entry].self, from: payload[start.lowerBound ..< end]),
               !entries.isEmpty {
                return entries
            }
            cursor = start.upperBound
        }
        return nil
    }

    /// Index after the `]` that closes the array opening at `start`, skipping brackets inside strings.
    static func endOfArray(in data: Data, from start: Data.Index) -> Data.Index? {
        var depth = 0
        var inString = false
        var escaped = false
        for index in start ..< data.endIndex {
            let byte = data[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "["): depth += 1
            case UInt8(ascii: "]"):
                depth -= 1
                if depth == 0 {
                    return data.index(after: index)
                }
            default: break
            }
        }
        return nil
    }

    /// One element of the page's augment array. `name` and `rarity` are `null` for augments OP.GG
    /// still tracks but the game no longer offers.
    struct Entry: Decodable {
        let id: Int
        let tier: Int
        let popular: Double
        let name: String?
        let rarity: Int?
        let smallIcon: String?

        var stat: AugmentStat? {
            guard let name, !name.isEmpty else { return nil }
            return AugmentStat(
                id: id,
                name: name,
                tier: tier,
                popularity: popular,
                rarity: rarity.flatMap(AugmentStat.Rarity.init(opgg:)),
                iconURL: smallIcon.flatMap(URL.init(string:))
            )
        }
    }
}
