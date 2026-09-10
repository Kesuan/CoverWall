#!/usr/bin/env swift
import AppKit
import Foundation

// Rasterize Design/AppIcon/icon-light.svg and icon-dark.svg to opaque square PNGs.
// Geometry is a 1:1 Core Graphics twin of the two Swiss-geometric SVGs.
// Usage: swift render_swiss_icons.swift <output_dir> <size> [<size> ...]

func hex(_ s: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: s.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
    return NSColor(
        red: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: 1
    )
}

enum Mode {
    case light
    case dark

    var bg: NSColor {
        switch self {
        case .light: return hex("#EDE4D0")
        case .dark: return hex("#222628")
        }
    }
    var disc: NSColor {
        switch self {
        case .light: return hex("#2F3334")
        case .dark: return hex("#E8DFC8")
        }
    }
    var knock: NSColor {
        bg
    }
    var phone: NSColor { hex("#D9481A") }
}

func draw(_ mode: Mode, size: Int) -> CGImage? {
    let side = CGFloat(size)
    let scale = side / 1024
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }

    ctx.translateBy(x: 0, y: side)
    ctx.scaleBy(x: scale, y: -scale)

    // Opaque square field (App Store / system mask). Design viewBox is already 1024.
    ctx.setFillColor(mode.bg.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))

    // Disc half-clipped by diagonal polygon: (0,0) (715,0) (373,1024) (0,1024)
    let discPath = CGMutablePath()
    discPath.addEllipse(in: CGRect(x: 398 - 302, y: 512 - 302, width: 604, height: 604))
    let clipPoly = CGMutablePath()
    clipPoly.move(to: CGPoint(x: 0, y: 0))
    clipPoly.addLine(to: CGPoint(x: 715, y: 0))
    clipPoly.addLine(to: CGPoint(x: 373, y: 1024))
    clipPoly.addLine(to: CGPoint(x: 0, y: 1024))
    clipPoly.closeSubpath()

    ctx.saveGState()
    ctx.addPath(clipPoly)
    ctx.clip()
    ctx.setFillColor(mode.disc.cgColor)
    ctx.addPath(discPath)
    ctx.fillPath()
    ctx.restoreGState()

    // Thick ring (hole of the disc)
    ctx.setStrokeColor(mode.knock.cgColor)
    ctx.setLineWidth(56)
    ctx.strokeEllipse(in: CGRect(x: 412 - 118, y: 518 - 118, width: 236, height: 236))

    // Diagonal band through the disc
    ctx.setStrokeColor(mode.knock.cgColor)
    ctx.setLineWidth(64)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: 418, y: 818))
    ctx.addLine(to: CGPoint(x: 612, y: 238))
    ctx.strokePath()

    // Phone / wallpaper plate
    let phone = CGMutablePath()
    let px: CGFloat = 575, py: CGFloat = 248, pw: CGFloat = 276, ph: CGFloat = 568, pr: CGFloat = 42
    phone.move(to: CGPoint(x: px + pr, y: py))
    phone.addLine(to: CGPoint(x: px + pw - pr, y: py))
    phone.addArc(tangent1End: CGPoint(x: px + pw, y: py), tangent2End: CGPoint(x: px + pw, y: py + pr), radius: pr)
    phone.addLine(to: CGPoint(x: px + pw, y: py + ph - pr))
    phone.addArc(tangent1End: CGPoint(x: px + pw, y: py + ph), tangent2End: CGPoint(x: px + pw - pr, y: py + ph), radius: pr)
    phone.addLine(to: CGPoint(x: px + pr, y: py + ph))
    phone.addArc(tangent1End: CGPoint(x: px, y: py + ph), tangent2End: CGPoint(x: px, y: py + ph - pr), radius: pr)
    phone.addLine(to: CGPoint(x: px, y: py + pr))
    phone.addArc(tangent1End: CGPoint(x: px, y: py), tangent2End: CGPoint(x: px + pr, y: py), radius: pr)
    phone.closeSubpath()
    ctx.setFillColor(mode.phone.cgColor)
    ctx.addPath(phone)
    ctx.fillPath()

    return ctx.makeImage()
}

func save(_ image: CGImage, to url: URL, size: Int) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: CGFloat(size), height: CGFloat(size))
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 2)
    }
    try data.write(to: url)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: swift render_swiss_icons.swift <out_dir> <size>...\n".utf8))
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
let sizes = args.dropFirst(2).compactMap { Int($0) }
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for size in sizes {
    for mode in [Mode.light, Mode.dark] {
        guard let image = draw(mode, size: size) else {
            FileHandle.standardError.write(Data("failed \(mode) \(size)\n".utf8))
            exit(1)
        }
        let name = (mode == .light) ? "AppIcon-Light-\(size).png" : "AppIcon-Dark-\(size).png"
        let url = outDir.appendingPathComponent(name)
        try save(image, to: url, size: size)
        print("wrote \(url.path)")
    }
}
