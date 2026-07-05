// Measures the left content inset of a window screenshot, in pixels: the
// smallest x, across sampled rows below the title bar, where a pixel departs
// from that row's right-edge background sample. Prints the integer to stdout.
//
// Run: swift Tests/screenshots/measure-inset.swift <window.png>
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: measure-inset.swift <image.png>\n".utf8))
    exit(2)
}
guard let data = FileManager.default.contents(atPath: CommandLine.arguments[1]),
      let rep = NSBitmapImageRep(data: data) else {
    FileHandle.standardError.write(Data("measure-inset: cannot read image\n".utf8))
    exit(2)
}

let width = rep.pixelsWide
let height = rep.pixelsHigh

func srgb(_ color: NSColor?) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
    guard let c = color?.usingColorSpace(.sRGB) else { return nil }
    return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
}

func distance(
    _ a: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
    _ b: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
) -> CGFloat {
    let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
    return (dr * dr + dg * dg + db * db).squareRoot()
}

// Skip the title bar at the top and the rounded corners at the bottom. The
// alpha guard skips the transparent pixels outside the window's corner radius
// (screencapture -o captures without a shadow, corners stay transparent).
var minX = width
for y in stride(from: Int(Double(height) * 0.2), to: Int(Double(height) * 0.95), by: 4) {
    guard let background = srgb(rep.colorAt(x: width - 4, y: y)), background.a > 0.9 else { continue }
    for x in 0..<(width / 2) {
        guard let pixel = srgb(rep.colorAt(x: x, y: y)), pixel.a > 0.9 else { continue }
        if distance(pixel, background) > 0.2 {
            if x < minX { minX = x }
            break
        }
    }
}

guard minX < width else {
    FileHandle.standardError.write(Data("measure-inset: no content found in image\n".utf8))
    exit(1)
}
print(minX)
