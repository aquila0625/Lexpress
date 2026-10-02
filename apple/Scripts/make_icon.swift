// 生成 App 图标。在 apple/ 目录下运行：
//   swiftc -O Scripts/make_icon.swift -o build/make_icon && build/make_icon [A|B|C|D]
// 不带参数时用方案 A。iOS 用整张铺满的方图（系统自己裁圆角），macOS 用带边距的圆角方块。
import AppKit

let outDir = "Shared/Assets.xcassets/AppIcon.appiconset"
let concept = CommandLine.arguments.count > 1 ? CommandLine.arguments[1].uppercased() : "A"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func pingfang(_ size: CGFloat) -> NSFont {
    NSFont(name: "PingFangSC-Semibold", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
}

/// 按字形的实际墨迹范围居中，而不是带行距的排版框
func text(_ string: String, font: NSFont, color: NSColor, center: NSPoint) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]))
    let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    let context = NSGraphicsContext.current!.cgContext
    context.textPosition = CGPoint(x: center.x - ink.midX, y: center.y - ink.midY)
    CTLineDraw(line, context)
}

func polygon(_ points: [NSPoint]) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: points[0])
    points.dropFirst().forEach { path.line(to: $0) }
    path.close()
    return path
}

func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }

/// 填充并用同色圆角描边，把尖角磨圆
func soft(_ path: NSBezierPath, _ fill: NSColor, round: CGFloat = 28) {
    fill.set()
    path.lineJoinStyle = .round
    path.lineWidth = round
    path.fill()
    path.stroke()
}

func line(from: NSPoint, to: NSPoint, width: CGFloat, _ stroke: NSColor) {
    let path = NSBezierPath()
    path.move(to: from)
    path.line(to: to)
    path.lineWidth = width
    path.lineCapStyle = .round
    stroke.set()
    path.stroke()
}

/// 整体向右倾斜，带一点速度感
func slanted(_ amount: CGFloat, _ body: () -> Void) {
    let context = NSGraphicsContext.current!.cgContext
    context.saveGState()
    context.translateBy(x: 512, y: 512)
    context.concatenate(CGAffineTransform(a: 1, b: 0, c: amount, d: 1, tx: 0, ty: 0))
    context.translateBy(x: -512, y: -512)
    body()
    context.restoreGState()
}

// 以下四个方案都画在 1024×1024 的坐标里，原点在左下角。

/// A：L 的一横变成箭头，指向“文” —— 英文到中文，快
func conceptA() {
    soft(polygon([pt(236, 796), pt(372, 796), pt(372, 384), pt(628, 384), pt(628, 468), pt(822, 316),
                  pt(628, 164), pt(628, 248), pt(236, 248)]), .white)
    text("文", font: pingfang(350), color: .white, center: pt(640, 660))
}

/// B：摊开的词典，中缝是一道闪电 —— 词典，快
func conceptB() {
    func page(_ sign: CGFloat, _ fill: NSColor) {
        func x(_ offset: CGFloat) -> CGFloat { 512 + sign * offset }
        let path = NSBezierPath()
        path.move(to: pt(x(26), 716))
        path.curve(to: pt(x(352), 760), controlPoint1: pt(x(120), 790), controlPoint2: pt(x(250), 790))
        path.line(to: pt(x(352), 310))
        path.curve(to: pt(x(26), 266), controlPoint1: pt(x(250), 340), controlPoint2: pt(x(120), 340))
        path.close()
        soft(path, fill, round: 30)
    }
    page(-1, .white)
    page(1, color(0xFFFFFF, 0.78))
    let bolt = polygon([pt(590, 880), pt(392, 520), pt(506, 520), pt(440, 150), pt(640, 580), pt(522, 580)])
    color(0x0B63E6).set()
    bolt.lineJoinStyle = .round
    bolt.lineWidth = 64
    bolt.stroke()
    soft(bolt, color(0xFFB21A), round: 16)
}

/// C：Lx 字标，x 的一笔是橙色 —— 品牌缩写
func conceptC() {
    slanted(0.16) {
        soft(polygon([pt(196, 790), pt(336, 790), pt(336, 374), pt(500, 374), pt(500, 234), pt(196, 234)]), .white, round: 24)
        line(from: pt(560, 294), to: pt(820, 600), width: 118, .white)
        line(from: pt(560, 600), to: pt(820, 294), width: 118, color(0xFFB21A))
    }
}

/// D：倾斜的“译”字加三道速度线 —— 快译
func conceptD() {
    slanted(0.2) {
        text("译", font: pingfang(560), color: .white, center: pt(596, 512))
        line(from: pt(118, 660), to: pt(268, 660), width: 46, color(0xFFFFFF, 0.72))
        line(from: pt(64, 512), to: pt(268, 512), width: 46, color(0xFFFFFF, 0.72))
        line(from: pt(150, 364), to: pt(268, 364), width: 46, color(0xFFFFFF, 0.72))
    }
}

func drawLogo() {
    // 和 App 里的主色一致：亮蓝到天蓝
    NSGradient(colors: [color(0x0A5CE0), color(0x34A4FF)])!.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), angle: 50)
    switch concept {
    case "B": conceptB()
    case "C": conceptC()
    case "D": conceptD()
    default: conceptA()
    }
}

func render(size: Int, fullBleed: Bool) -> CGImage {
    // App Store 要求 iOS 图标不带透明通道，所以铺满的那张用不透明的位图
    let alpha: CGImageAlphaInfo = fullBleed ? .noneSkipLast : .premultipliedLast
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    if fullBleed {
        drawLogo()
    } else {
        let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
        let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowOffset = NSSize(width: 0, height: -12 * CGFloat(size) / 1024)
        shadow.shadowBlurRadius = 28 * CGFloat(size) / 1024
        shadow.set()
        NSColor.black.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        context.translateBy(x: 100, y: 100)
        context.scaleBy(x: 824.0 / 1024, y: 824.0 / 1024)
        drawLogo()
        NSGraphicsContext.restoreGraphicsState()
    }
    return context.makeImage()!
}

func write(_ image: CGImage, _ name: String) throws {
    let url = URL(fileURLWithPath: "\(outDir)/\(name)") as CFURL
    guard let destination = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
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
print("已生成方案 \(concept)：\(outDir)")
