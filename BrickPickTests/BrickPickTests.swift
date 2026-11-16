import CoreGraphics
import Foundation
import Testing
@testable import BrickPick

private func color(_ name: String) -> LegoColor { LegoColor.named(name)! }
private func index(_ name: String) -> Int { LegoColor.common.firstIndex(of: color(name))! }
private let commonLUT = PaletteLUT(palette: .common)

private func makeAnalyzer(target: String? = nil) -> FrameAnalyzer {
    var analyzer = FrameAnalyzer()
    analyzer.lut = target.map { PaletteLUT(palette: .common, targetIndex: index($0)) } ?? commonLUT
    return analyzer
}

/// Runs a 180×320 BGRA frame through the analyzer; `colorAt` gives the colour of each pixel.
private func analyze(_ analyzer: inout FrameAnalyzer, colorAt: (_ x: Int, _ y: Int) -> RGB) -> FrameAnalyzer.Output {
    let width = 180, height = 320
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let c = colorAt(x, y)
            let i = (y * width + x) * 4
            pixels[i] = c.b
            pixels[i + 1] = c.g
            pixels[i + 2] = c.r
        }
    }
    return pixels.withUnsafeBufferPointer {
        analyzer.analyze(Frame(base: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4))
    }
}

/// A frame whose left and right halves are solid colours.
private func analyze(left: RGB, right: RGB, analyzer: inout FrameAnalyzer) -> FrameAnalyzer.Output {
    analyze(&analyzer) { x, _ in x < 90 ? left : right }
}

/// A brick-sized patch in the middle of the frame: mask columns 35..<55, rows 65..<95.
private func analyze(patch: RGB, on background: RGB, analyzer: inout FrameAnalyzer) -> FrameAnalyzer.Output {
    analyze(&analyzer) { x, y in (70..<110).contains(x) && (130..<190).contains(y) ? patch : background }
}

private func alphas(_ mask: CGImage) -> [UInt8] {
    let data = mask.dataProvider!.data! as Data
    return stride(from: 3, to: data.count, by: 4).map { data[$0] }
}

struct ColorMathTests {
    // Reference pairs from Sharma, Wu & Dalal's CIEDE2000 test data.
    @Test(arguments: [
        (Lab(l: 50, a: 2.6772, b: -79.7751), Lab(l: 50, a: 0, b: -82.7485), 2.0425),
        (Lab(l: 50, a: 3.1571, b: -77.2803), Lab(l: 50, a: 0, b: -82.7485), 2.8615),
        (Lab(l: 50, a: 2.5, b: 0), Lab(l: 50, a: 0, b: -2.5), 4.3065),
        (Lab(l: 50, a: 2.5, b: 0), Lab(l: 73, a: 25, b: -18), 27.1492),
    ])
    func deltaEMatchesReference(p: Lab, q: Lab, expected: Double) {
        #expect(abs(ColorMath.deltaE(p, q) - expected) < 0.0001)
        #expect(abs(ColorMath.deltaE(q, p) - expected) < 0.0001)
    }

    @Test func labOfWhiteAndBlack() {
        let white = ColorMath.lab(RGB(hex: 0xFFFFFF))
        #expect(abs(white.l - 100) < 0.01 && abs(white.a) < 0.01 && abs(white.b) < 0.01)
        #expect(abs(ColorMath.lab(RGB(hex: 0x000000)).l) < 0.01)
    }

    @Test func encodeInvertsLinear() {
        for value in UInt8.min...UInt8.max {
            #expect(ColorMath.encode(ColorMath.linear(value)) == value)
        }
    }
}

struct MatchingTests {
    @Test func paletteNamesAreUnique() {
        #expect(Set(LegoColor.common.map(\.name)).count == LegoColor.common.count)
    }

    @Test func everyPaletteColourReadsAsItself() {
        for color in LegoColor.common {
            let reading = Reading(sample: color.rgb)
            #expect(reading.best == color)
            #expect(reading.alternatives.isEmpty, "\(color.name) is ambiguous with \(reading.alternatives.map(\.name))")
            #expect(reading.verdict(for: color) == .match)
        }
    }

    @Test func lookupTableAgreesWithPalette() {
        for (index, color) in LegoColor.common.enumerated() {
            #expect(commonLUT.paletteIndex(r: color.rgb.r, g: color.rgb.g, b: color.rgb.b) == index, "\(color.name)")
        }
    }

    @Test func verdicts() {
        let red = Reading(sample: color("Red").rgb)
        #expect(red.verdict(for: color("Dark Red")) == .noMatch)
        #expect(red.verdict(for: color("Green")) == .noMatch)

        // Halfway between Red and Dark Red cannot be called either way.
        let between = Reading(sample: RGB(r: 0x9A, g: 0x14, b: 0x0C))
        #expect(Set([between.best] + between.alternatives) == [color("Red"), color("Dark Red")])
        #expect(between.verdict(for: color("Red")) == .possible)
        #expect(between.verdict(for: color("Dark Red")) == .possible)
        #expect(between.verdict(for: color("Blue")) == .noMatch)
    }
}

struct BundleTests {
    @Test func licenceIsBundled() throws {
        let url = try #require(Bundle.main.url(forResource: "LICENSE", withExtension: nil))
        #expect(try String(contentsOf: url, encoding: .utf8).hasPrefix("MIT License"))
    }
}

struct SetTests {
    @Test func bundledColoursLoad() {
        #expect(LegoColor.all.count > 150)
        #expect(Set(LegoColor.all.map(\.name)).count == LegoColor.all.count)
        #expect(LegoColor.common.count == 41)
        #expect(color("Red").rgb == RGB(hex: 0xC91A09))
    }

    @Test func findsSetsByNumberAndName() throws {
        let bookshop = try #require(SetCatalog.set(numbered: "10270-1"))
        #expect(bookshop.name == "Bookshop")
        #expect(bookshop.displayNumber == "10270")
        #expect(bookshop.colors.contains(color("Sand Green")))
        #expect(bookshop.colors.count == bookshop.colorIDs.count)

        // The set has 2,504 pieces; transparent ones are not counted.
        let counts = bookshop.brickCounts
        #expect(counts.count == bookshop.colors.count)
        #expect((2000...2504).contains(counts.values.reduce(0, +)))
        #expect(counts.values.allSatisfy { $0 > 0 })
        #expect(counts[color("Sand Green")]! > counts[color("Lavender")] ?? 0)

        #expect(SetCatalog.search("10270").first == bookshop)
        #expect(SetCatalog.search("bookshop").contains(bookshop))
        #expect(SetCatalog.search("falcon millennium").contains { $0.number == "75192-1" })
        #expect(SetCatalog.search("  ").isEmpty)
        #expect(SetCatalog.search("a").count == 50)
    }

    @Test func readingIsLimitedToThePalette() {
        // Within a set that has no Dark Red, a dark red sample can only be Red.
        let palette = Palette([color("Red"), color("Blue"), color("White")])
        let reading = Reading(sample: color("Dark Red").rgb, palette: palette)
        #expect(reading.best == color("Red"))
        #expect(reading.candidates.count == 3)

        let lut = PaletteLUT(palette: palette)
        let darkRed = color("Dark Red").rgb
        #expect(lut.paletteIndex(r: darkRed.r, g: darkRed.g, b: darkRed.b) == 0)
    }
}

struct ShadingTests {
    /// The same surface with more or less light on it.
    private func lit(_ rgb: RGB, _ factor: Double) -> RGB {
        RGB(
            r: ColorMath.encode(ColorMath.linear(rgb.r) * factor),
            g: ColorMath.encode(ColorMath.linear(rgb.g) * factor),
            b: ColorMath.encode(ColorMath.linear(rgb.b) * factor)
        )
    }

    @Test func shadedBrickStillCountsAsTheTarget() {
        for name in ["Tan", "Red", "Blue", "Green", "Medium Lavender"] {
            let lut = PaletteLUT(palette: .common, targetIndex: index(name))
            for factor in [0.7, 0.85, 1.0] {
                let seen = lit(color(name).rgb, factor)
                #expect(lut.couldBeTarget(r: seen.r, g: seen.g, b: seen.b), "\(name) at \(factor)")
                #expect(Reading(sample: seen).verdict(for: color(name)) != .noMatch, "\(name) at \(factor)")
            }
        }
    }

    @Test func otherHuesNeverCountAsTheTarget() {
        let lut = PaletteLUT(palette: .common, targetIndex: index("Tan"))
        for name in ["Light Bluish Gray", "White", "Dark Bluish Gray", "Yellow", "Olive Green", "Sand Green", "Bright Pink"] {
            for factor in [0.7, 1.0] {
                let seen = lit(color(name).rgb, factor)
                #expect(!lut.couldBeTarget(r: seen.r, g: seen.g, b: seen.b), "\(name) at \(factor)")
            }
        }
    }
}

struct TeachingTests {
    @Test func taughtSampleChangesTheReading() {
        let yellows = [color("Yellow"), color("Vibrant Yellow"), color("Bright Light Orange")]
        // A warm yellow, as a camera might record a Vibrant Yellow brick.
        let seen = RGB(r: 0xE8, g: 0xC0, b: 0x30)
        let untaught = Palette(yellows)
        #expect(Reading(sample: seen, palette: untaught).best != color("Vibrant Yellow"))

        let taught = Palette(yellows, learned: ["Vibrant Yellow": [seen]])
        let reading = Reading(sample: seen, palette: taught)
        #expect(reading.best == color("Vibrant Yellow"))
        #expect(reading.candidates[0].distance == 0)
        #expect(PaletteLUT(palette: taught).paletteIndex(r: seen.r, g: seen.g, b: seen.b) == 1)

        // The catalogue values still read as themselves.
        for yellow in yellows {
            #expect(Reading(sample: yellow.rgb, palette: taught).best == yellow)
        }
    }
}

struct CalibrationTests {
    /// What the camera would record for a surface under dim, warm light.
    private func dimWarm(_ rgb: RGB) -> RGB {
        RGB(
            r: ColorMath.encode(ColorMath.linear(rgb.r) * 0.45),
            g: ColorMath.encode(ColorMath.linear(rgb.g) * 0.33),
            b: ColorMath.encode(ColorMath.linear(rgb.b) * 0.18)
        )
    }

    @Test func removesColourCast() throws {
        // White paper reflects about 90% of the light.
        let paper = RGB(r: ColorMath.encode(0.9), g: ColorMath.encode(0.9), b: ColorMath.encode(0.9))
        let calibration = try #require(Calibration(whiteSample: dimWarm(paper)))

        for name in ["White", "Red", "Dark Red", "Blue", "Light Bluish Gray", "Dark Bluish Gray", "Tan", "Lime"] {
            let seen = dimWarm(color(name).rgb)
            #expect(Reading(sample: calibration.apply(seen)).best == color(name), "\(name)")
        }
        // Without calibration the cast gives wrong answers.
        #expect(Reading(sample: dimWarm(color("White").rgb)).best != color("White"))
    }

    @Test func rejectsUnusableWhite() {
        #expect(Calibration(whiteSample: RGB(r: 255, g: 255, b: 255)) == nil)
        #expect(Calibration(whiteSample: RGB(r: 20, g: 20, b: 20)) == nil)
    }

    @Test func identityChangesNothing() {
        let sample = RGB(r: 12, g: 130, b: 250)
        #expect(Calibration.identity.apply(sample) == sample)
    }
}

struct FrameAnalyzerTests {
    @Test func readsCentreColour() {
        var analyzer = makeAnalyzer()
        let output = analyze(left: color("Blue").rgb, right: color("Blue").rgb, analyzer: &analyzer)
        #expect(output.reading.best == color("Blue"))
        #expect(output.rawSample == color("Blue").rgb)
        #expect(output.mask == nil)
        #expect(!output.isTooDark)
    }

    @Test func maskOutlinesTheTarget() throws {
        var analyzer = makeAnalyzer(target: "Red")
        let output = analyze(patch: color("Red").rgb, on: color("Dark Red").rgb, analyzer: &analyzer)
        let mask = try #require(output.mask)
        let alpha = alphas(mask)

        for row in 0..<mask.height {
            // Speck removal rounds the patch's corners off by one cell; leave those out.
            for col in 0..<mask.width where !([34, 35, 54, 55].contains(col) && [64, 65, 94, 95].contains(row)) {
                let isPatch = (35..<55).contains(col) && (65..<95).contains(row)
                let isOutline = !isPatch && (34..<56).contains(col) && (64..<96).contains(row)
                let expected: UInt8 = isPatch ? 0 : isOutline ? 255 : FrameAnalyzer.dimAlpha
                #expect(alpha[row * mask.width + col] == expected, "column \(col), row \(row)")
            }
        }
    }

    @Test func maskIgnoresSpecks() throws {
        // One 2×2 red speck (a single mask cell) on a blue frame.
        var analyzer = makeAnalyzer(target: "Red")
        let output = analyze(&analyzer) { x, y in
            (40...41).contains(x) && (60...61).contains(y) ? color("Red").rgb : color("Blue").rgb
        }
        #expect(alphas(try #require(output.mask)).allSatisfy { $0 == FrameAnalyzer.dimAlpha })
    }

    @Test func maskIgnoresRegionsTooBigToBeABrick() throws {
        // A wall or table top in the target colour.
        var analyzer = makeAnalyzer(target: "Red")
        let wall = analyze(left: color("Red").rgb, right: color("Red").rgb, analyzer: &analyzer)
        #expect(alphas(try #require(wall.mask)).allSatisfy { $0 == FrameAnalyzer.dimAlpha })
        let half = analyze(left: color("Red").rgb, right: color("Blue").rgb, analyzer: &analyzer)
        #expect(alphas(try #require(half.mask)).allSatisfy { $0 == FrameAnalyzer.dimAlpha })
    }

    @Test func maskIgnoresColoursFarFromTheTarget() throws {
        // Something off-palette, like a painted wall: it has a nearest colour, but is not close to it.
        let levels = stride(from: 4, to: 256, by: 8).map { UInt8($0) }
        var found: (sample: RGB, nearest: LegoColor)?
        search: for r in levels {
            for g in levels {
                for b in levels {
                    let reading = Reading(sample: RGB(r: r, g: g, b: b))
                    if reading.candidates[0].distance > PaletteLUT.maxTargetDistance + 1 {
                        found = (RGB(r: r, g: g, b: b), reading.best)
                        break search
                    }
                }
            }
        }
        let wall = try #require(found)
        var analyzer = makeAnalyzer(target: wall.nearest.name)
        let output = analyze(left: wall.sample, right: wall.sample, analyzer: &analyzer)
        #expect(output.reading.best == wall.nearest)
        #expect(alphas(try #require(output.mask)).allSatisfy { $0 == FrameAnalyzer.dimAlpha })
    }

    @Test func maskFollowsCalibration() throws {
        // Under a warm cast, Light Bluish Gray only reads correctly once calibrated.
        func cast(_ rgb: RGB) -> RGB {
            RGB(
                r: ColorMath.encode(ColorMath.linear(rgb.r) * 0.5),
                g: ColorMath.encode(ColorMath.linear(rgb.g) * 0.35),
                b: ColorMath.encode(ColorMath.linear(rgb.b) * 0.2)
            )
        }
        let paper = RGB(r: ColorMath.encode(0.9), g: ColorMath.encode(0.9), b: ColorMath.encode(0.9))
        let seen = cast(color("Light Bluish Gray").rgb)

        let background = cast(color("Blue").rgb)

        var analyzer = makeAnalyzer(target: "Light Bluish Gray")
        let uncalibrated = analyze(patch: seen, on: background, analyzer: &analyzer)
        #expect(alphas(try #require(uncalibrated.mask)).allSatisfy { $0 == FrameAnalyzer.dimAlpha })

        analyzer.calibration = try #require(Calibration(whiteSample: cast(paper)))
        let output = analyze(patch: seen, on: background, analyzer: &analyzer)
        #expect(output.reading.best == color("Light Bluish Gray"))
        let mask = try #require(output.mask)
        #expect(alphas(mask)[80 * mask.width + 45] == 0)
    }

    @Test func flagsDarkFrames() {
        var analyzer = makeAnalyzer()
        let dark = RGB(r: 10, g: 12, b: 9)
        #expect(analyze(left: dark, right: dark, analyzer: &analyzer).isTooDark)
    }

    @Test func smoothsNoiseButFollowsJumps() {
        var analyzer = makeAnalyzer()
        _ = analyze(left: RGB(r: 100, g: 100, b: 100), right: RGB(r: 100, g: 100, b: 100), analyzer: &analyzer)
        let nudged = analyze(left: RGB(r: 110, g: 100, b: 100), right: RGB(r: 110, g: 100, b: 100), analyzer: &analyzer)
        #expect(nudged.rawSample == RGB(r: 103, g: 100, b: 100))
        let jumped = analyze(left: color("Blue").rgb, right: color("Blue").rgb, analyzer: &analyzer)
        #expect(jumped.rawSample == color("Blue").rgb)
    }
}
