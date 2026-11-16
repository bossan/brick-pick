import CoreGraphics
import Foundation

/// A BGRA video frame in portrait orientation.
struct Frame {
    let base: UnsafePointer<UInt8>
    let width: Int
    let height: Int
    let bytesPerRow: Int
}

/// Turns video frames into a colour reading at the centre of the frame and a mask
/// that outlines the target colour and dims everything else.
struct FrameAnalyzer {
    /// Opacity of the black laid over everything that is not the target colour.
    static let dimAlpha: UInt8 = 120
    /// Target-coloured regions with fewer mask cells than this are treated as noise.
    static let minRegionCells = 16
    /// Target-coloured regions covering more of the frame than this are taken to be a wall
    /// or table top rather than a brick.
    static let maxRegionFraction = 0.15

    var calibration = Calibration.identity
    /// The colours a sample can be read as.
    var palette = Palette.common
    /// Lookup table for `palette` and the target colour; without it there is no mask.
    var lut: PaletteLUT?

    private var smoothed: (r: Double, g: Double, b: Double)?

    struct Output {
        /// Centre sample before calibration.
        let rawSample: RGB
        /// Centre sample after calibration; what the reading is based on.
        let sample: RGB
        let reading: Reading
        /// Clear over the target colour with a white outline around it, translucent black
        /// elsewhere; nil without a target or lookup table.
        let mask: CGImage?
        let isTooDark: Bool
    }

    mutating func analyze(_ frame: Frame) -> Output {
        let raw = smooth(centerSample(frame))
        let sample = calibration.apply(raw)
        let (mask, isTooDark) = scan(frame)
        return Output(
            rawSample: raw,
            sample: sample,
            reading: Reading(sample: sample, palette: palette),
            mask: mask,
            isTooDark: isTooDark
        )
    }

    /// Per-channel median of a small patch at the centre; the median ignores glare and stud shadows.
    private func centerSample(_ f: Frame) -> RGB {
        let side = max(4, f.width / 16)
        let step = max(1, side / 15)
        var r = [UInt8](), g = [UInt8](), b = [UInt8]()
        for y in stride(from: f.height / 2 - side / 2, to: f.height / 2 + side / 2, by: step) {
            for x in stride(from: f.width / 2 - side / 2, to: f.width / 2 + side / 2, by: step) {
                let p = f.base + y * f.bytesPerRow + x * 4
                b.append(p[0])
                g.append(p[1])
                r.append(p[2])
            }
        }
        r.sort()
        g.sort()
        b.sort()
        return RGB(r: r[r.count / 2], g: g[g.count / 2], b: b[b.count / 2])
    }

    /// Averages over recent frames to steady the readout, but follows large jumps immediately.
    private mutating func smooth(_ sample: RGB) -> RGB {
        let new = (r: Double(sample.r), g: Double(sample.g), b: Double(sample.b))
        if let s = smoothed, abs(s.r - new.r) < 24, abs(s.g - new.g) < 24, abs(s.b - new.b) < 24 {
            smoothed = (s.r + 0.3 * (new.r - s.r), s.g + 0.3 * (new.g - s.g), s.b + 0.3 * (new.b - s.b))
        } else {
            smoothed = new
        }
        let s = smoothed!
        return RGB(r: UInt8(s.r.rounded()), g: UInt8(s.g.rounded()), b: UInt8(s.b.rounded()))
    }

    /// Walks a coarse grid over the frame, measuring brightness and building the target mask.
    private func scan(_ f: Frame) -> (mask: CGImage?, isTooDark: Bool) {
        let step = max(2, f.width / 144)
        let half = step / 2
        let cols = f.width / step, rows = f.height / step
        let lut = self.lut?.hasTarget == true ? self.lut : nil
        var hits = lut == nil ? [] : [Bool](repeating: false, count: cols * rows)
        var lumaSum = 0

        for row in 0..<rows {
            let top = f.base + row * step * f.bytesPerRow
            let bottom = top + half * f.bytesPerRow
            for col in 0..<cols {
                // Average four pixels of the cell to tame sensor noise.
                let x = col * step * 4, x2 = x + half * 4
                let b = (Int(top[x]) + Int(top[x2]) + Int(bottom[x]) + Int(bottom[x2])) / 4
                let g = (Int(top[x + 1]) + Int(top[x2 + 1]) + Int(bottom[x + 1]) + Int(bottom[x2 + 1])) / 4
                let r = (Int(top[x + 2]) + Int(top[x2 + 2]) + Int(bottom[x + 2]) + Int(bottom[x2 + 2])) / 4
                lumaSum += (2 * r + 5 * g + b) / 8

                if let lut {
                    let c = calibration.apply(r: r, g: g, b: b)
                    hits[row * cols + col] = lut.couldBeTarget(r: c.r, g: c.g, b: c.b)
                }
            }
        }

        let isTooDark = lumaSum / max(1, cols * rows) < 35
        guard lut != nil else { return (nil, isTooDark) }

        // A cell counts as target only if most of its 3×3 neighbourhood does.
        // This drops the specks that glare and sensor noise leave behind.
        var inside = [Bool](repeating: false, count: cols * rows)
        hits.withUnsafeBufferPointer { hits in
            inside.withUnsafeMutableBufferPointer { inside in
                for row in 0..<rows {
                    for col in 0..<cols {
                        var count = 0, total = 0
                        for r in max(0, row - 1)...min(rows - 1, row + 1) {
                            for c in max(0, col - 1)...min(cols - 1, col + 1) {
                                total += 1
                                if hits[r * cols + c] { count += 1 }
                            }
                        }
                        inside[row * cols + col] = count * 2 > total
                    }
                }
            }
        }

        // Keep only regions that could be a brick: not tiny, and not most of the picture.
        let maxRegionCells = Int(Double(cols * rows) * FrameAnalyzer.maxRegionFraction)
        var visited = [Bool](repeating: false, count: cols * rows)
        var pending = [Int](), region = [Int]()
        for start in 0..<cols * rows where inside[start] && !visited[start] {
            region.removeAll(keepingCapacity: true)
            visited[start] = true
            pending.append(start)
            while let cell = pending.popLast() {
                region.append(cell)
                let col = cell % cols
                func visit(_ next: Int) {
                    if next >= 0, next < cols * rows, inside[next], !visited[next] {
                        visited[next] = true
                        pending.append(next)
                    }
                }
                visit(cell - cols)
                visit(cell + cols)
                if col > 0 { visit(cell - 1) }
                if col < cols - 1 { visit(cell + 1) }
            }
            if region.count < FrameAnalyzer.minRegionCells || region.count > maxRegionCells {
                for cell in region { inside[cell] = false }
            }
        }

        // Target cells stay clear, the cells bordering them form a white outline, the rest is dimmed.
        var pixels = [UInt8](repeating: 0, count: cols * rows * 4)
        inside.withUnsafeBufferPointer { inside in
            pixels.withUnsafeMutableBufferPointer { pixels in
                for row in 0..<rows {
                    for col in 0..<cols where !inside[row * cols + col] {
                        var isBorder = false
                        for r in max(0, row - 1)...min(rows - 1, row + 1) {
                            for c in max(0, col - 1)...min(cols - 1, col + 1) where inside[r * cols + c] {
                                isBorder = true
                            }
                        }
                        let i = (row * cols + col) * 4
                        if isBorder {
                            pixels[i] = 255
                            pixels[i + 1] = 255
                            pixels[i + 2] = 255
                            pixels[i + 3] = 255
                        } else {
                            pixels[i + 3] = FrameAnalyzer.dimAlpha
                        }
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return (nil, isTooDark) }
        let mask = CGImage(
            width: cols, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: cols * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
        return (mask, isTooDark)
    }
}
