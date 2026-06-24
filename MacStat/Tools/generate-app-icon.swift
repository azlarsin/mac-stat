#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

private let outputDirectory = URL(fileURLWithPath: "MacStat/MacStat/Assets.xcassets/AppIcon.appiconset")

private struct IconSlot {
    let filename: String
    let pixels: Int
}

private let slots: [IconSlot] = [
    IconSlot(filename: "icon_16x16.png", pixels: 16),
    IconSlot(filename: "icon_16x16@2x.png", pixels: 32),
    IconSlot(filename: "icon_32x32.png", pixels: 32),
    IconSlot(filename: "icon_32x32@2x.png", pixels: 64),
    IconSlot(filename: "icon_128x128.png", pixels: 128),
    IconSlot(filename: "icon_128x128@2x.png", pixels: 256),
    IconSlot(filename: "icon_256x256.png", pixels: 256),
    IconSlot(filename: "icon_256x256@2x.png", pixels: 512),
    IconSlot(filename: "icon_512x512.png", pixels: 512),
    IconSlot(filename: "icon_512x512@2x.png", pixels: 1024),
]

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xff) / 255
    let g = CGFloat((hex >> 8) & 0xff) / 255
    let b = CGFloat(hex & 0xff) / 255
    return CGColor(red: r, green: g, blue: b, alpha: alpha)
}

private func gradient(_ stops: [(UInt32, CGFloat)]) -> CGGradient {
    let colors = stops.map { color($0.0) } as CFArray
    let locations = stops.map(\.1)
    return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations)!
}

private func alphaGradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    let colors = stops.map { color($0.0, alpha: $0.1) } as CFArray
    let locations = stops.map(\.2)
    return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations)!
}

private func drawRoundedRect(
    in context: CGContext,
    rect: CGRect,
    radius: CGFloat,
    fill: CGColor,
    stroke: CGColor? = nil,
    lineWidth: CGFloat = 1
) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(path)
    context.setFillColor(fill)
    context.fillPath()

    if let stroke {
        context.addPath(path)
        context.setStrokeColor(stroke)
        context.setLineWidth(lineWidth)
        context.strokePath()
    }
}

private func strokePolyline(_ points: [CGPoint], in context: CGContext, width: CGFloat, color: CGColor) {
    guard let first = points.first else { return }
    context.beginPath()
    context.move(to: first)
    for point in points.dropFirst() {
        context.addLine(to: point)
    }
    context.setLineJoin(.round)
    context.setLineCap(.round)
    context.setLineWidth(width)
    context.setStrokeColor(color)
    context.strokePath()
}

private func strokeArc(
    center: CGPoint,
    radius: CGFloat,
    startDegrees: CGFloat,
    endDegrees: CGFloat,
    in context: CGContext,
    width: CGFloat,
    color: CGColor
) {
    context.beginPath()
    context.addArc(
        center: center,
        radius: radius,
        startAngle: startDegrees * .pi / 180,
        endAngle: endDegrees * .pi / 180,
        clockwise: false
    )
    context.setLineCap(.round)
    context.setLineWidth(width)
    context.setStrokeColor(color)
    context.strokePath()
}

private func renderIcon(size: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let baseRect = CGRect(x: 74, y: 74, width: 876, height: 876)
    let basePath = CGPath(roundedRect: baseRect, cornerWidth: 204, cornerHeight: 204, transform: nil)

    context.addPath(basePath)
    context.setFillColor(color(0x111820))
    context.fillPath()

    context.saveGState()
    context.addPath(basePath)
    context.clip()

    context.drawLinearGradient(
        gradient([(0x273241, 0), (0x151c25, 0.58), (0x0b1016, 1)]),
        start: CGPoint(x: 512, y: 950),
        end: CGPoint(x: 512, y: 74),
        options: []
    )

    context.setBlendMode(.screen)
    context.drawRadialGradient(
        alphaGradient([(0x20d7d0, 0.32, 0), (0x20d7d0, 0, 1)]),
        startCenter: CGPoint(x: 300, y: 755),
        startRadius: 0,
        endCenter: CGPoint(x: 300, y: 755),
        endRadius: 450,
        options: []
    )
    context.drawRadialGradient(
        alphaGradient([(0xff8a2a, 0.28, 0), (0xff8a2a, 0, 1)]),
        startCenter: CGPoint(x: 766, y: 292),
        startRadius: 0,
        endCenter: CGPoint(x: 766, y: 292),
        endRadius: 360,
        options: []
    )
    context.setBlendMode(.normal)
    context.restoreGState()

    context.addPath(basePath)
    context.setStrokeColor(color(0xffffff, alpha: 0.16))
    context.setLineWidth(3)
    context.strokePath()

    let chipRect = CGRect(x: 260, y: 278, width: 504, height: 468)
    let chipPath = CGPath(roundedRect: chipRect, cornerWidth: 92, cornerHeight: 92, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 28, color: color(0x000000, alpha: 0.36))
    context.addPath(chipPath)
    context.setFillColor(color(0x15202a))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(chipPath)
    context.clip()
    context.drawLinearGradient(
        gradient([(0x2b3a49, 0), (0x111923, 1)]),
        start: CGPoint(x: 512, y: 746),
        end: CGPoint(x: 512, y: 278),
        options: []
    )
    context.restoreGState()

    context.addPath(chipPath)
    context.setStrokeColor(color(0x82fff3, alpha: 0.20))
    context.setLineWidth(4)
    context.strokePath()

    let pinColor = color(0x9be7e1, alpha: 0.32)
    context.setLineCap(.round)
    context.setLineWidth(22)
    context.setStrokeColor(pinColor)
    for y in stride(from: CGFloat(348), through: CGFloat(676), by: 66) {
        context.move(to: CGPoint(x: 226, y: y))
        context.addLine(to: CGPoint(x: 260, y: y))
        context.move(to: CGPoint(x: 764, y: y))
        context.addLine(to: CGPoint(x: 798, y: y))
    }
    for x in stride(from: CGFloat(338), through: CGFloat(688), by: 70) {
        context.move(to: CGPoint(x: x, y: 244))
        context.addLine(to: CGPoint(x: x, y: 278))
        context.move(to: CGPoint(x: x, y: 746))
        context.addLine(to: CGPoint(x: x, y: 780))
    }
    context.strokePath()

    let gaugeCenter = CGPoint(x: 512, y: 512)
    strokeArc(center: gaugeCenter, radius: 344, startDegrees: 205, endDegrees: 336, in: context, width: 34, color: color(0x1fd5cf, alpha: 0.88))
    strokeArc(center: gaugeCenter, radius: 344, startDegrees: 336, endDegrees: 382, in: context, width: 34, color: color(0xff8d34, alpha: 0.95))
    strokeArc(center: gaugeCenter, radius: 284, startDegrees: 210, endDegrees: 378, in: context, width: 10, color: color(0xffffff, alpha: 0.13))

    let mutedLine = color(0xffffff, alpha: 0.12)
    strokePolyline([CGPoint(x: 346, y: 398), CGPoint(x: 346, y: 640)], in: context, width: 16, color: mutedLine)
    strokePolyline([CGPoint(x: 432, y: 398), CGPoint(x: 432, y: 642)], in: context, width: 16, color: mutedLine)
    strokePolyline([CGPoint(x: 518, y: 398), CGPoint(x: 518, y: 642)], in: context, width: 16, color: mutedLine)
    strokePolyline([CGPoint(x: 604, y: 398), CGPoint(x: 604, y: 642)], in: context, width: 16, color: mutedLine)

    let graphPoints = [
        CGPoint(x: 335, y: 430),
        CGPoint(x: 430, y: 505),
        CGPoint(x: 512, y: 480),
        CGPoint(x: 610, y: 610),
        CGPoint(x: 690, y: 575),
    ]
    context.saveGState()
    context.setShadow(offset: .zero, blur: 18, color: color(0x2ef7ec, alpha: 0.48))
    strokePolyline(graphPoints, in: context, width: 34, color: color(0x2ef7ec, alpha: 0.30))
    context.restoreGState()
    strokePolyline(graphPoints, in: context, width: 20, color: color(0x38efe7, alpha: 1))

    for point in graphPoints {
        context.setFillColor(color(0xdffffd))
        context.fillEllipse(in: CGRect(x: point.x - 13, y: point.y - 13, width: 26, height: 26))
    }

    let thermoRect = CGRect(x: 644, y: 368, width: 58, height: 174)
    drawRoundedRect(in: context, rect: thermoRect, radius: 29, fill: color(0x0f161e), stroke: color(0xff9d45, alpha: 0.95), lineWidth: 16)
    context.setFillColor(color(0xff8d34))
    context.fillEllipse(in: CGRect(x: 629, y: 328, width: 88, height: 88))
    drawRoundedRect(in: context, rect: CGRect(x: 669, y: 392, width: 8, height: 126), radius: 4, fill: color(0xff8d34, alpha: 0.94))

    context.saveGState()
    context.addPath(basePath)
    context.clip()
    context.setBlendMode(.screen)
    context.drawLinearGradient(
        alphaGradient([(0xffffff, 0.22, 0), (0xffffff, 0, 1)]),
        start: CGPoint(x: 512, y: 950),
        end: CGPoint(x: 512, y: 540),
        options: []
    )
    context.restoreGState()

    return context.makeImage()!
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for slot in slots {
    let image = renderIcon(size: slot.pixels)
    try writePNG(image, to: outputDirectory.appendingPathComponent(slot.filename))
    print("wrote \(slot.filename)")
}
