// 生成 AppIcon.icns：swift Resources/make_icon.swift（在工程根目录运行）
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS 图标规范：1024 画布里放 824 的圆角方块
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.42, blue: 0.98, alpha: 1),
                    NSColor(srgbRed: 0.16, green: 0.62, blue: 0.96, alpha: 1)])!
    .draw(in: shape, angle: -60)

func draw(_ text: String, font: NSFont, color: NSColor, center: NSPoint) {
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let bounds = string.boundingRect(with: .zero, options: [.usesLineFragmentOrigin])
    string.draw(at: NSPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
}

// 左上小 “A”，右下大 “译”，表示 英 ⇄ 中
draw("A", font: .systemFont(ofSize: 210, weight: .bold), color: NSColor.white.withAlphaComponent(0.6),
     center: NSPoint(x: 285, y: 745))
draw("译", font: NSFont(name: "PingFangSC-Semibold", size: 450) ?? .systemFont(ofSize: 450, weight: .semibold),
     color: .white, center: NSPoint(x: 590, y: 425))

NSGraphicsContext.current?.flushGraphics()

let fm = FileManager.default
let iconset = "Resources/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let master = "\(iconset)/icon_512x512@2x.png"
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: master))

func run(_ tool: String, _ args: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    try p.run()
    p.waitUntilExit()
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] where !(base == 512 && scale == 2) {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try run("/usr/bin/sips", ["-z", "\(base * scale)", "\(base * scale)", master, "--out", "\(iconset)/\(name)"])
    }
}
try run("/usr/bin/iconutil", ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"])
try fm.copyItem(atPath: master, toPath: "Resources/AppIcon-preview.png")
try fm.removeItem(atPath: iconset)
print("已生成 Resources/AppIcon.icns")
