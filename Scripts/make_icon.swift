#!/usr/bin/env swift
// Draws the app icon: a 2×2 brick seen from above inside camera viewfinder brackets.
// Usage: swift Scripts/make_icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("BrickPick/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255, alpha: 1
    )
}

let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: rgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

// Background: dark, like the camera view the app lives in.
let background = CGGradient(
    colorsSpace: rgb, colors: [color(0x2A3040), color(0x0D0F15)] as CFArray, locations: [0, 1]
)!
context.drawLinearGradient(
    background, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: []
)

// Brick: yellow on dark stays distinct for every type of colour vision.
let brickSide = 480.0
let depth = 34.0
let center = CGPoint(x: size / 2, y: size / 2 + depth / 2)
let brick = CGRect(
    x: center.x - brickSide / 2, y: center.y - brickSide / 2, width: brickSide, height: brickSide
)
func roundedRect(_ rect: CGRect, radius: Double) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

context.addPath(roundedRect(brick.offsetBy(dx: 0, dy: -depth), radius: 52))
context.setFillColor(color(0xB58A12))
context.fillPath()
context.addPath(roundedRect(brick, radius: 52))
context.setFillColor(color(0xF2CD37))
context.fillPath()

// Four studs, each with a shaded side.
let studRadius = 76.0
let studDepth = 20.0
for dx in [-1.0, 1.0] {
    for dy in [-1.0, 1.0] {
        let stud = CGRect(
            x: center.x + dx * brickSide / 4 - studRadius, y: center.y + dy * brickSide / 4 - studRadius,
            width: studRadius * 2, height: studRadius * 2
        )
        context.setFillColor(color(0xB58A12))
        context.fillEllipse(in: stud.offsetBy(dx: 0, dy: -studDepth / 2))
        context.setFillColor(color(0xFBDD5C))
        context.fillEllipse(in: stud.offsetBy(dx: 0, dy: studDepth / 2))
    }
}

// Viewfinder brackets around the brick.
let frameSide = 724.0
let arm = 120.0
let radius = 96.0
let half = frameSide / 2
context.setStrokeColor(color(0xFFFFFF))
context.setLineWidth(44)
context.setLineCap(.round)
for sx in [-1.0, 1.0] {
    for sy in [-1.0, 1.0] {
        let corner = CGPoint(x: size / 2 + sx * half, y: size / 2 + sy * half)
        context.move(to: CGPoint(x: corner.x - sx * (radius + arm), y: corner.y))
        context.addArc(
            tangent1End: corner, tangent2End: CGPoint(x: corner.x, y: corner.y - sy * (radius + arm)),
            radius: radius
        )
        context.addLine(to: CGPoint(x: corner.x, y: corner.y - sy * (radius + arm)))
        context.strokePath()
    }
}

let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(output.path)") }
print("Wrote \(output.path)")
