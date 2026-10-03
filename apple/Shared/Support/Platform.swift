import ImageIO
import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

extension PlatformImage {
    /// Vision 需要位图本身和它的拍摄方向
    var visionInput: (image: CGImage, orientation: CGImagePropertyOrientation)? {
        #if os(macOS)
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return (cgImage, .up)
        #else
        guard let cgImage else { return nil }
        let orientation: CGImagePropertyOrientation
        switch imageOrientation {
        case .up: orientation = .up
        case .down: orientation = .down
        case .left: orientation = .left
        case .right: orientation = .right
        case .upMirrored: orientation = .upMirrored
        case .downMirrored: orientation = .downMirrored
        case .leftMirrored: orientation = .leftMirrored
        case .rightMirrored: orientation = .rightMirrored
        @unknown default: orientation = .up
        }
        return (cgImage, orientation)
        #endif
    }
}

extension PlatformImage {
    /// 存到本机时用的 JPEG 数据
    var storageData: Data? {
        #if os(macOS)
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        #else
        return jpegData(compressionQuality: 0.85)
        #endif
    }
}

extension PlatformImage {
    /// 顺时针转 90°
    func rotatedClockwise() -> PlatformImage {
        let target = CGSize(width: size.height, height: size.width)
        #if os(macOS)
        let rotated = NSImage(size: target)
        rotated.lockFocus()
        let transform = NSAffineTransform()
        transform.translateX(by: target.width / 2, yBy: target.height / 2)
        transform.rotate(byDegrees: -90)
        transform.concat()
        draw(in: NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        rotated.unlockFocus()
        return rotated
        #else
        return UIGraphicsImageRenderer(size: target).image { context in
            context.cgContext.translateBy(x: target.width / 2, y: target.height / 2)
            context.cgContext.rotate(by: .pi / 2)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
        #endif
    }
}

extension View {
    /// iOS 上用小标题；Mac 没有这个概念
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

extension Notification.Name {
    /// 窗口被呼出时，让输入框获得焦点并全选
    static let focusInput = Notification.Name("QTranslator.focusInput")
}
