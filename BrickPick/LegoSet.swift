import Foundation

/// A LEGO set and the solid colours of its parts.
struct LegoSet: Identifiable, Hashable {
    /// Rebrickable set number, e.g. "10270-1".
    let number: String
    let name: String
    let year: Int
    /// Rebrickable ids of the set's colours; see `LegoColor.catalogID`.
    let colorIDs: [Int]
    /// How many bricks of the set have each of those colours, spares excluded.
    let quantities: [Int]

    var id: String { number }

    /// The number as printed on the box: without the "-1" variant suffix.
    var displayNumber: String {
        number.hasSuffix("-1") ? String(number.dropLast(2)) : number
    }

    var colors: [LegoColor] {
        colorIDs.compactMap { LegoColor.byCatalogID[$0] }
    }

    /// Number of bricks per colour.
    var brickCounts: [LegoColor: Int] {
        var counts = [LegoColor: Int]()
        for (id, quantity) in zip(colorIDs, quantities) {
            if let color = LegoColor.byCatalogID[id] { counts[color] = quantity }
        }
        return counts
    }
}

enum SetCatalog {
    /// All sets in the bundled Rebrickable table, newest first. Parsed on first use,
    /// which takes a moment, so touch it off the main thread.
    static let all: [LegoSet] = {
        guard let url = Bundle.main.url(forResource: "sets", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t")
            guard fields.count == 4, let year = Int(fields[2]) else { return nil }
            // Each entry is "colour:bricks".
            let bricks = fields[3].split(separator: ",").compactMap { entry -> (Int, Int)? in
                let pair = entry.split(separator: ":")
                guard pair.count == 2, let color = Int(pair[0]), let quantity = Int(pair[1]) else { return nil }
                return (color, quantity)
            }
            return LegoSet(
                number: String(fields[0]),
                name: String(fields[1]),
                year: year,
                colorIDs: bricks.map(\.0),
                quantities: bricks.map(\.1)
            )
        }
    }()

    static func set(numbered number: String) -> LegoSet? {
        all.first { $0.number == number }
    }

    /// Sets whose number starts with, or whose name contains, every word of the query.
    /// Number matches come first; within each group the newest sets lead.
    static func search(_ query: String, limit: Int = 50) -> [LegoSet] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }

        var byNumber = [LegoSet](), byName = [LegoSet]()
        for set in all {
            if words.count == 1, set.number.hasPrefix(words[0]) {
                byNumber.append(set)
            } else if byName.count < limit, words.allSatisfy({
                set.name.localizedCaseInsensitiveContains($0) || set.number.hasPrefix($0)
            }) {
                byName.append(set)
            }
        }
        return Array((byNumber + byName).prefix(limit))
    }
}
