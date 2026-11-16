import Foundation

struct ColorMatch {
    let color: LegoColor
    let distance: Double
}

enum MatchVerdict {
    case match
    case possible
    case noMatch
}

/// The colours a sample can be read as. Each has one or more reference points:
/// its catalogue value plus any samples the user has taught the app.
struct Palette: Sendable {
    static let common = Palette(LegoColor.common)

    /// Lightness counts for a third. Shading and glare change how light a brick looks far
    /// more than its hue, and light versus dark is what a colour-blind eye can judge itself.
    static let lightnessTolerance = 3.0

    let colors: [LegoColor]
    private let references: [(lab: Lab, color: Int)]

    /// `learned` maps colour names to camera samples known to be that colour.
    init(_ colors: [LegoColor], learned: [String: [RGB]] = [:]) {
        self.colors = colors
        references = colors.enumerated().flatMap { index, color in
            [(color.lab, index)] + (learned[color.name] ?? []).map { (ColorMath.lab($0), index) }
        }
    }

    /// ΔE from a sample to the nearest reference point of each colour.
    func distances(to lab: Lab) -> [Double] {
        var distances = [Double](repeating: .infinity, count: colors.count)
        for reference in references {
            distances[reference.color] = min(
                distances[reference.color],
                ColorMath.deltaE(lab, reference.lab, lightnessTolerance: Palette.lightnessTolerance)
            )
        }
        return distances
    }
}

/// What the camera sees under the reticle: the nearest palette colours, closest first.
struct Reading {
    /// Runner-ups this close (in ΔE) to the best match cannot be told apart reliably.
    static let ambiguityMargin = 3.0

    let candidates: [ColorMatch]

    init(sample: RGB, palette: Palette = .common) {
        candidates = zip(palette.colors, palette.distances(to: ColorMath.lab(sample)))
            .map { ColorMatch(color: $0, distance: $1) }
            .sorted { $0.distance < $1.distance }
            .prefix(3)
            .map { $0 }
    }

    var best: LegoColor { candidates[0].color }

    /// Other colours the sample could just as well be.
    var alternatives: [LegoColor] {
        candidates.dropFirst()
            .filter { $0.distance - candidates[0].distance < Reading.ambiguityMargin }
            .map(\.color)
    }

    func verdict(for target: LegoColor) -> MatchVerdict {
        if best == target {
            return alternatives.isEmpty ? .match : .possible
        }
        return alternatives.contains(target) ? .possible : .noMatch
    }
}

/// Classifies every sRGB value, quantised to 32 levels per channel, against one palette,
/// so whole frames can be handled cheaply. Building it takes a moment.
final class PaletteLUT: Sendable {
    /// Values further than this (in ΔE) from the target never count as the target,
    /// so walls and tables mostly stay out of the mask.
    static let maxTargetDistance = 12.0

    let hasTarget: Bool
    private let nearest: [UInt8]
    private let couldBeTarget: [Bool]

    /// `targetIndex` is the position in the palette of the colour being looked for.
    init(palette: Palette, targetIndex: Int? = nil) {
        var nearest = [UInt8](repeating: 0, count: 32 * 32 * 32)
        var couldBeTarget = [Bool](repeating: false, count: 32 * 32 * 32)
        for r in 0..<32 {
            for g in 0..<32 {
                for b in 0..<32 {
                    // Classify the centre of the cell.
                    let lab = ColorMath.lab(RGB(r: UInt8(r << 3 | 4), g: UInt8(g << 3 | 4), b: UInt8(b << 3 | 4)))
                    let distances = palette.distances(to: lab)
                    var bestIndex = 0
                    for (index, distance) in distances.enumerated() where distance < distances[bestIndex] {
                        bestIndex = index
                    }
                    let cell = r << 10 | g << 5 | b
                    nearest[cell] = UInt8(bestIndex)
                    if let targetIndex {
                        // Same rule as a reading's "match or maybe".
                        couldBeTarget[cell] = distances[targetIndex] <= PaletteLUT.maxTargetDistance
                            && distances[targetIndex] - distances[bestIndex] < Reading.ambiguityMargin
                    }
                }
            }
        }
        self.nearest = nearest
        self.couldBeTarget = couldBeTarget
        hasTarget = targetIndex != nil
    }

    /// Index into the palette of the colour nearest to the given sRGB value.
    func paletteIndex(r: UInt8, g: UInt8, b: UInt8) -> Int {
        Int(nearest[Int(r >> 3) << 10 | Int(g >> 3) << 5 | Int(b >> 3)])
    }

    /// Whether the given sRGB value is, or cannot be told apart from, the target colour.
    func couldBeTarget(r: UInt8, g: UInt8, b: UInt8) -> Bool {
        couldBeTarget[Int(r >> 3) << 10 | Int(g >> 3) << 5 | Int(b >> 3)]
    }
}

/// Per-channel correction derived from a white reference, so that readings are
/// independent of the colour and brightness of the room light.
struct Calibration {
    /// Linear reflectance a white reference is mapped to.
    private static let referenceWhite = 0.9

    private let r: [UInt8]
    private let g: [UInt8]
    private let b: [UInt8]

    static let identity = Calibration(gains: (1, 1, 1))

    private init(gains: (Double, Double, Double)) {
        func table(_ gain: Double) -> [UInt8] {
            (0...255).map { ColorMath.encode(ColorMath.linear(UInt8($0)) * gain) }
        }
        r = table(gains.0)
        g = table(gains.1)
        b = table(gains.2)
    }

    /// Fails when the sample is clipped or too dark to be a usable white reference.
    init?(whiteSample s: RGB) {
        guard [s.r, s.g, s.b].allSatisfy({ (40..<250).contains($0) }) else { return nil }
        self.init(gains: (
            Calibration.referenceWhite / ColorMath.linear(s.r),
            Calibration.referenceWhite / ColorMath.linear(s.g),
            Calibration.referenceWhite / ColorMath.linear(s.b)
        ))
    }

    func apply(_ rgb: RGB) -> RGB {
        RGB(r: r[Int(rgb.r)], g: g[Int(rgb.g)], b: b[Int(rgb.b)])
    }

    @inline(__always)
    func apply(r red: Int, g green: Int, b blue: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        (r[red], g[green], b[blue])
    }
}
