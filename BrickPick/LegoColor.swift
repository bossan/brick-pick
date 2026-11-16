import Foundation

/// A solid LEGO colour, named as on BrickLink / Rebrickable.
struct LegoColor: Identifiable, Hashable {
    let name: String
    let rgb: RGB
    let lab: Lab
    /// Colour id in the Rebrickable catalogue; sets refer to colours by it.
    let catalogID: Int

    var id: String { name }

    init(_ name: String, _ hex: UInt32, catalogID: Int) {
        self.name = name
        self.catalogID = catalogID
        self.rgb = RGB(hex: hex)
        self.lab = ColorMath.lab(rgb)
    }

    static func == (lhs: LegoColor, rhs: LegoColor) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }

    static func named(_ name: String) -> LegoColor? {
        all.first { $0.name == name }
    }

    /// Every solid colour in the bundled Rebrickable table (see Scripts/build_set_data.py).
    /// Transparent colours are left out: a camera cannot read them reliably.
    static let all: [LegoColor] = {
        guard let url = Bundle.main.url(forResource: "colors", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t")
            guard fields.count == 3, let id = Int(fields[0]), let hex = UInt32(fields[2], radix: 16) else { return nil }
            return LegoColor(String(fields[1]), hex, catalogID: id)
        }
    }()

    static let byCatalogID = Dictionary(all.map { ($0.catalogID, $0) }, uniquingKeysWith: { first, _ in first })

    /// The colours matched against when no set is chosen: the common ones in current sets.
    static let common: [LegoColor] = [
        "White", "Light Bluish Gray", "Dark Bluish Gray", "Black",
        "Red", "Dark Red", "Coral",
        "Blue", "Dark Blue", "Medium Blue", "Bright Light Blue", "Dark Azure", "Medium Azure", "Sand Blue",
        "Yellow", "Bright Light Yellow", "Bright Light Orange", "Orange", "Dark Orange",
        "Green", "Dark Green", "Bright Green", "Lime", "Yellowish Green", "Olive Green", "Sand Green",
        "Dark Turquoise", "Light Aqua",
        "Tan", "Dark Tan", "Reddish Brown", "Dark Brown", "Medium Nougat", "Nougat", "Light Nougat",
        "Bright Pink", "Dark Pink", "Magenta", "Dark Purple", "Medium Lavender", "Lavender",
    ].compactMap(named)
}
