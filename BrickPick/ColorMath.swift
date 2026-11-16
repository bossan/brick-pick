import Foundation

/// An 8-bit sRGB colour.
struct RGB: Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        self.init(r: UInt8((hex >> 16) & 0xFF), g: UInt8((hex >> 8) & 0xFF), b: UInt8(hex & 0xFF))
    }
}

/// A colour in CIE L*a*b* (D65).
struct Lab {
    var l: Double
    var a: Double
    var b: Double
}

enum ColorMath {
    /// sRGB-encoded 8-bit value to linear light in 0...1.
    static func linear(_ value: UInt8) -> Double {
        let v = Double(value) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    /// Linear light to an sRGB-encoded 8-bit value, clamped.
    static func encode(_ value: Double) -> UInt8 {
        let v = min(max(value, 0), 1)
        let encoded = v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
        return UInt8((encoded * 255).rounded())
    }

    static func lab(_ rgb: RGB) -> Lab {
        let r = linear(rgb.r), g = linear(rgb.g), b = linear(rgb.b)
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883

        func f(_ t: Double) -> Double {
            t > 216.0 / 24389.0 ? cbrt(t) : (24389.0 / 27.0 * t + 16) / 116
        }
        let fx = f(x), fy = f(y), fz = f(z)
        return Lab(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    /// CIEDE2000 colour difference. A `lightnessTolerance` above 1 makes differences in
    /// lightness count for less (the formula's kL).
    static func deltaE(_ p: Lab, _ q: Lab, lightnessTolerance: Double = 1) -> Double {
        func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }
        func hue(_ b: Double, _ a: Double) -> Double {
            if a == 0 && b == 0 { return 0 }
            let h = atan2(b, a) * 180 / .pi
            return h < 0 ? h + 360 : h
        }
        let pow25to7 = 6103515625.0

        let cBar = (hypot(p.a, p.b) + hypot(q.a, q.b)) / 2
        let g = 0.5 * (1 - sqrt(pow(cBar, 7) / (pow(cBar, 7) + pow25to7)))
        let a1 = (1 + g) * p.a, a2 = (1 + g) * q.a
        let c1 = hypot(a1, p.b), c2 = hypot(a2, q.b)
        let h1 = hue(p.b, a1), h2 = hue(q.b, a2)

        let dL = q.l - p.l
        let dC = c2 - c1
        var dh = 0.0
        var hBar = h1 + h2
        if c1 * c2 != 0 {
            dh = h2 - h1
            if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 }

            if abs(h1 - h2) <= 180 {
                hBar = (h1 + h2) / 2
            } else if h1 + h2 < 360 {
                hBar = (h1 + h2 + 360) / 2
            } else {
                hBar = (h1 + h2 - 360) / 2
            }
        }
        let dH = 2 * sqrt(c1 * c2) * sin(rad(dh / 2))

        let lBar = (p.l + q.l) / 2
        let cBarPrime = (c1 + c2) / 2
        let t = 1 - 0.17 * cos(rad(hBar - 30)) + 0.24 * cos(rad(2 * hBar))
            + 0.32 * cos(rad(3 * hBar + 6)) - 0.20 * cos(rad(4 * hBar - 63))
        let dTheta = 30 * exp(-pow((hBar - 275) / 25, 2))
        let rC = 2 * sqrt(pow(cBarPrime, 7) / (pow(cBarPrime, 7) + pow25to7))
        let sL = 1 + 0.015 * pow(lBar - 50, 2) / sqrt(20 + pow(lBar - 50, 2))
        let sC = 1 + 0.045 * cBarPrime
        let sH = 1 + 0.015 * cBarPrime * t
        let rT = -sin(rad(2 * dTheta)) * rC

        return sqrt(pow(dL / (lightnessTolerance * sL), 2) + pow(dC / sC, 2) + pow(dH / sH, 2) + rT * (dC / sC) * (dH / sH))
    }
}
