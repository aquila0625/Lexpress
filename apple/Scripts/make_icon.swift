// 生成 App 图标：在 apple/ 目录下运行 `swift Scripts/make_icon.swift`
// iOS 用整张铺满的方图（系统自己裁圆角），macOS 用带边距的圆角方块。
import AppKit

let outDir = "Shared/Assets.xcassets/AppIcon.appiconset"

func render(size: Int, fullBleed: Bool) -> NSBitmapImageRep {
    // App Store 要求 iOS 图标不带透明通道
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: fullBleed ? 3 : 4, hasAlpha: !fullBleed, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: s)
    transform.concat()

    let tile = fullBleed ? NSRect(x: 0, y: 0, width: 1024, height: 1024) : NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = fullBleed ? NSBezierPath(rect: tile) : NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    if !fullBleed {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowOffset = NSSize(width: 0, height: -12 * s)
        shadow.shadowBlurRadius = 28 * s
        shadow.set()
        NSColor.black.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    // 和 App 里的主色一致：亮蓝到天蓝
    NSGradient(colors: [NSColor(srgbRed: 0.04, green: 0.42, blue: 0.94, alpha: 1),
                        NSColor(srgbRed: 0.22, green: 0.66, blue: 1.00, alpha: 1)])!
        .draw(in: shape, angle: -60)

    func draw(_ text: String, font: NSFont, color: NSColor, center: NSPoint) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let bounds = string.boundingRect(with: .zero, options: [.usesLineFragmentOrigin])
        string.draw(at: NSPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
    }

    // 左上小 “A”，右下大 “译”，表示 英 ⇄ 中
    let k: CGFloat = fullBleed ? 1.12 : 1   // 铺满时没有边距，内容相应放大一点
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: 512 + (x - 512) * k, y: 512 + (y - 512) * k) }
    draw("A", font: .systemFont(ofSize: 210 * k, weight: .bold), color: NSColor.white.withAlphaComponent(0.65), center: p(285, 745))
    draw("译", font: NSFont(name: "PingFangSC-Semibold", size: 450 * k) ?? .systemFont(ofSize: 450 * k, weight: .semibold),
         color: .white, center: p(590, 425))

    NSGraphicsContext.current?.flushGraphics()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ name: String) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
try write(render(size: 1024, fullBleed: true), "ios-1024.png")
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try write(render(size: size, fullBleed: false), "mac-\(size).png")
}

let mac: [(String, String, Int)] = [("16x16", "1x", 16), ("16x16", "2x", 32), ("32x32", "1x", 32), ("32x32", "2x", 64),
                                     ("128x128", "1x", 128), ("128x128", "2x", 256), ("256x256", "1x", 256),
                                     ("256x256", "2x", 512), ("512x512", "1x", 512), ("512x512", "2x", 1024)]
var images: [[String: String]] = [["filename": "ios-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]]
images += mac.map { ["filename": "mac-\($0.2).png", "idiom": "mac", "scale": $0.1, "size": $0.0] }
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: "\(outDir)/Contents.json"))
print("已生成 \(outDir)")
