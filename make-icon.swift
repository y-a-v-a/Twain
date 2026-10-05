#!/usr/bin/env swift
// Regenerates Twain.icns and public/twain-icon.png from the Icon Composer source
// Twain.icon. Run from the repo root after editing the icon: `./make-icon.swift`.
//
// Needs Xcode 26+ (Icon Composer's ictool). The app still ships the committed .icns
// because CI builds with Xcode 16, which can't compile .icon documents.
//
// ictool renders the bare squircle edge to edge; .icns images follow the macOS grid
// instead (an 824pt body centred in 1024pt, with a drop shadow), so each size is
// rendered at body size and composited onto a transparent canvas here.

import AppKit

let ictool = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("twain-icon-\(getpid())")
let iconset = tmp.appendingPathComponent("Twain.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }

func run(_ path: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    try! p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { fatalError("\(path) \(args) failed") }
}

/// Renders the squircle at `size` px with ictool and returns it as a CGImage.
func renderBody(_ size: Int) -> CGImage {
    let out = tmp.appendingPathComponent("body-\(size).png")
    run(ictool, ["Twain.icon", "--export-image", "--output-file", out.path, "--platform", "macOS",
                 "--rendition", "Default", "--width", "\(size)", "--height", "\(size)", "--scale", "1"])
    let src = CGImageSourceCreateWithURL(out as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
}

/// Places the rendered body on the macOS icon grid for a `px`-sized canvas.
func gridIcon(_ px: Int) -> CGImage {
    let margin = Int(Double(px) * 100 / 1024)
    let body = px - 2 * margin
    let k = CGFloat(px) / 1024
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * k), blur: 28 * k,
                  color: CGColor(gray: 0, alpha: 0.3))
    ctx.draw(renderBody(body), in: CGRect(x: margin, y: margin, width: body, height: body))
    return ctx.makeImage()!
}

for px in [16, 32, 64, 128, 256, 512, 1024] {
    let image = gridIcon(px)
    let names = [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                 (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"),
                 (1024, "512x512@2x")].filter { $0.0 == px }.map(\.1)
    for name in names {
        writePNG(image, to: iconset.appendingPathComponent("icon_\(name).png"))
    }
}
run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", "Twain.icns"])

// The docs page rounds and shadows the image itself, so it gets the bare squircle.
writePNG(renderBody(256), to: URL(fileURLWithPath: "public/twain-icon.png"))
print("Wrote Twain.icns and public/twain-icon.png")
