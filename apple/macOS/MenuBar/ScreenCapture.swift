import AppKit

/// 截图翻译用的框选截图。直接调用系统自带的截图工具，体验和 ⌘⇧4 一样：
/// 拖出一块区域，或按空格选整个窗口，按 Esc 取消。
enum ScreenCapture {
    /// 有没有“屏幕录制”权限。没有时截到的只有桌面背景
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// 框选一块区域并返回截图；取消时返回 nil
    static func selectRegion() async -> NSImage? {
        // 第一次用时让系统弹出授权提示
        if !hasPermission { CGRequestScreenCaptureAccess() }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("q-translator-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", url.path]   // -i 交互框选，-x 不出快门声
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume()
            }
        }
        guard let data = try? Data(contentsOf: url) else {
            log.info("screenshot: cancelled or no file, status \(process.terminationStatus, privacy: .public)")
            return nil
        }
        let image = NSImage(data: data)
        let pixels = image?.representations.first.map { "\($0.pixelsWide)x\($0.pixelsHigh)" } ?? "?"
        log.info("screenshot: \(data.count, privacy: .public) bytes, \(pixels, privacy: .public), permission \(hasPermission, privacy: .public)")
        return image
    }
}
