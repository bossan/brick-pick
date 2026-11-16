import CoreGraphics
import Observation
import SwiftUI

/// App state: what the camera currently sees and which colour the user is looking for.
@MainActor
@Observable
final class Scanner {
    enum State {
        case starting
        case running
        case unavailable
    }

    private static let targetKey = "targetColor"
    private static let setKey = "selectedSet"
    private static let learnedKey = "learnedColors"
    /// Taught samples kept per colour; older ones are dropped.
    private static let maxLearnedSamples = 5

    private(set) var state = State.starting
    private(set) var reading: Reading?
    private(set) var mask: CGImage?
    private(set) var isTooDark = false
    private(set) var isCalibrated = false
    /// The calibrated colour under the reticle.
    private(set) var sample: RGB?
    /// The set being built; limits the colours to the ones in that set.
    private(set) var selectedSet: LegoSet?

    var target: LegoColor? {
        didSet {
            UserDefaults.standard.set(target?.name, forKey: Scanner.targetKey)
            applyPalette()
        }
    }

    /// The colours a brick can be read as.
    var palette: [LegoColor] {
        if let colors = selectedSet?.colors, !colors.isEmpty { return colors }
        return LegoColor.common
    }

    var torchOn = false {
        didSet {
            camera.setTorch(torchOn)
            // The light changed, so the white reference no longer holds.
            resetCalibration()
        }
    }

    let camera = Camera()
    private var rawSample: RGB?
    /// Camera samples the user has said are a given colour, by colour name.
    private var learned: [String: [RGB]] = [:]

    var hasLearned: Bool { !learned.isEmpty }

    init() {
        let saved = UserDefaults.standard.dictionary(forKey: Scanner.learnedKey) as? [String: [Int]] ?? [:]
        learned = saved.mapValues { $0.map { RGB(hex: UInt32($0)) } }
        target = UserDefaults.standard.string(forKey: Scanner.targetKey).flatMap(LegoColor.named)
        applyPalette()
        camera.onOutput = { [weak self] output in
            MainActor.assumeIsolated { self?.handle(output) }
        }
    }

    var verdict: MatchVerdict? {
        guard let target, let reading else { return nil }
        return reading.verdict(for: target)
    }

    func start() async {
        state = await camera.start() ? .running : .unavailable
        if let number = UserDefaults.standard.string(forKey: Scanner.setKey) {
            selectedSet = await Task.detached { SetCatalog.set(numbered: number) }.value
            applyPalette()
        }
    }

    /// Pass nil to go back to the common colours.
    func selectSet(_ set: LegoSet?) {
        selectedSet = set
        UserDefaults.standard.set(set?.number, forKey: Scanner.setKey)
        if let target, !palette.contains(target) {
            self.target = nil
        } else {
            applyPalette()
        }
    }

    /// Records that `sample` is really `color`, so similar readings are named correctly from now on.
    func teach(_ color: LegoColor, sample: RGB) {
        learned[color.name] = Array((learned[color.name, default: []] + [sample]).suffix(Scanner.maxLearnedSamples))
        saveLearned()
    }

    func forgetLearned() {
        learned = [:]
        saveLearned()
    }

    private func saveLearned() {
        let saved = learned.mapValues { $0.map { Int($0.r) << 16 | Int($0.g) << 8 | Int($0.b) } }
        UserDefaults.standard.set(saved, forKey: Scanner.learnedKey)
        applyPalette()
    }

    private func applyPalette() {
        camera.setPalette(Palette(palette, learned: learned), targetIndex: target.flatMap(palette.firstIndex))
    }

    func setTargetFromReading() {
        target = reading?.best
    }

    /// Uses whatever is under the reticle as the white reference. Returns false if it is unusable.
    func calibrate() -> Bool {
        guard let rawSample, let calibration = Calibration(whiteSample: rawSample) else { return false }
        camera.setCalibration(calibration)
        isCalibrated = true
        return true
    }

    func resetCalibration() {
        camera.setCalibration(nil)
        isCalibrated = false
    }

    private func handle(_ output: FrameAnalyzer.Output) {
        rawSample = output.rawSample
        sample = output.sample
        reading = output.reading
        mask = output.mask
        isTooDark = output.isTooDark
    }
}
