// 生成 App 图标。在 apple/ 目录下运行：
//   swiftc -O Scripts/make_icon.swift -o build/make_icon && build/make_icon [E|F|G|H]
// 不带参数时用方案 E。四个方案都不含任何语言的文字，面向所有语言的用户。iOS 用整张铺满的方图（系统自己裁圆角），macOS 用带边距的圆角方块。
import AppKit

let outDir = "Shared/Assets.xcassets/AppIcon.appiconset"
let concept = CommandLine.arguments.count > 1 ? CommandLine.arguments[1].uppercased() : "E"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
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

let orange = color(0xFFA91F)

/// 圆角形状，可带对话气泡的小尾巴；半透明时整体合成，尾巴和主体之间不出接缝
func shape(_ rect: NSRect, radius: CGFloat, tail: [NSPoint] = [], alpha: CGFloat = 1) {
    let context = NSGraphicsContext.current!.cgContext
    context.saveGState()
    context.setAlpha(alpha)
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    NSColor.white.set()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    if !tail.isEmpty { soft(polygon(tail), .white, round: 22) }
    context.endTransparencyLayer()
    context.restoreGState()
}

/// 两个圆角矩形重叠的部分涂成橙色
func overlap(_ a: NSRect, _ b: NSRect, radius: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: a, xRadius: radius, yRadius: radius).addClip()
    orange.set()
    NSBezierPath(roundedRect: b, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()
}

// 以下四个方案都画在 1024×1024 的坐标里，原点在左下角。

/// E：两个对话气泡交叠，重合的部分是橙色 —— 两种语言，共同的意思
func conceptE() {
    let first = NSRect(x: 150, y: 430, width: 450, height: 400), second = NSRect(x: 420, y: 230, width: 450, height: 400)
    shape(second, radius: 96, tail: [pt(700, 250), pt(806, 128), pt(800, 250)], alpha: 0.6)
    shape(first, radius: 96, tail: [pt(224, 450), pt(218, 328), pt(330, 450)])
    overlap(first, second, radius: 96)
}

/// F：对话气泡里一道闪电 —— 说出来，马上懂
func conceptF() {
    shape(NSRect(x: 170, y: 330, width: 684, height: 500), radius: 170, tail: [pt(300, 352), pt(268, 176), pt(476, 352)])
    soft(polygon([pt(566, 790), pt(398, 560), pt(506, 560), pt(452, 372), pt(640, 610), pt(530, 610)]), orange, round: 18)
}

/// G：» 既是很多语言里的引号，也是“快进” —— 快的话语
func conceptG() {
    func chevron(_ x: CGFloat, alpha: CGFloat) {
        let context = NSGraphicsContext.current!.cgContext
        context.saveGState()
        context.setAlpha(alpha)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        let path = NSBezierPath()
        path.move(to: pt(x, 770))
        path.line(to: pt(x + 245, 512))
        path.line(to: pt(x, 254))
        path.lineWidth = 132
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.white.set()
        path.stroke()
        context.endTransparencyLayer()
        context.restoreGState()
    }
    chevron(270, alpha: 0.55)
    chevron(510, alpha: 1)
}

/// H：两根圆角条拼成 L，拐角重合处是橙色 —— 品牌首字母，两种语言在这里相接
func conceptH() {
    let vertical = NSRect(x: 236, y: 226, width: 214, height: 590), horizontal = NSRect(x: 236, y: 226, width: 570, height: 214)
    shape(horizontal, radius: 107, alpha: 0.6)
    shape(vertical, radius: 107)
    overlap(vertical, horizontal, radius: 107)
}

func drawLogo() {
    // 和 App 里的主色一致：亮蓝到天蓝
    NSGradient(colors: [color(0x0A5CE0), color(0x34A4FF)])!.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), angle: 50)
    switch concept {
    case "F": conceptF()
    case "G": conceptG()
    case "H": conceptH()
    default: conceptE()
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
