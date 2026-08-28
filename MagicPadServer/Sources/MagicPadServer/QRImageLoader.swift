// QRImageLoader.swift
// 按当前局域网 IP 动态生成 QR(CoreImage)，禁止打包写死静态 PNG。
// 缓存 key = 完整 URL；IP 变化时自动重生成。
// 主码永远 HTTP :7878（朋友/新设备 Safari·Chrome 能打开）。
// httpsReady 不得改写主码（录音自签在 :7879，另给 mobileHTTPSURL）。

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum QRImageLoader {
    static let readyNotification = Notification.Name("magicpad.qr.ready")

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedURL: String?
    nonisolated(unsafe) private static var cachedImage: NSImage?
    nonisolated(unsafe) private static var generating = false
    nonisolated(unsafe) private static var pendingURL: String?

    /// 主 QR 禁止 HTTPS。自签会让朋友/新设备直接打不开。
    static func preferHTTPS() -> Bool {
        false
    }

    /// 当前应编码进二维码的手机访问 URL（含 ?auto=1&host=）
    /// Host is `InstallEnvironment.healthLAN.ip` == `LANDetector.ip` (live iface).
    /// Port from last capture (7878). Same struct as /health httpUrl host.
    /// Does not read Resources/qr-mobile.png. Does not follow httpsReady / :7879.
    /// Pass `from:` so menu caption + pixels share one healthLAN snapshot.
    static func mobileURL(from lan: HealthLAN? = nil) -> String {
        let lan = lan ?? InstallEnvironment.healthLAN
        let url = lan.mobileURL
        if url.hasPrefix("http://"), url.contains("://\(lan.ip):") {
            return url
        }
        MagicLog.server("QR: repaired non-http or host-mismatch main URL")
        // Stay on the passed snapshot — do not re-read healthFields (could move).
        return "http://\(lan.ip):\(lan.httpPort)/?auto=1&host=\(lan.ip)"
    }

    /// 录音备用（自签，需「继续访问」）。不要印进主 QR。
    static func mobileHTTPSURL() -> String {
        let lan = InstallEnvironment.healthLAN
        return "https://\(lan.ip):\(lan.httpsPort)/?auto=1&host=\(lan.ip)"
    }

    /// Menu / MainActor: cache only. Never CoreImage here (and never the baked PNG).
    /// `matching` is the caption URL from the same body snapshot — avoids a second
    /// healthLAN read that could disagree with the text under the image.
    static func peek(matching expected: String? = nil) -> NSImage? {
        let url = expected ?? mobileURL()
        guard url.hasPrefix("http://") else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard cachedURL == url else { return nil }
        return cachedImage
    }

    /// 动态生成；仅当 HTTP URL（IP/端口）变了才重画。httpsReady 不得换 scheme。
    /// CoreImage stays off-main. Menu body should `peek()` after prepareOffMain.
    static func load() -> NSImage? {
        load(depth: 0)
    }

    private static func load(depth: Int) -> NSImage? {
        // handleLANChange / SwiftUI / attachHTTPS: never CoreImage on main
        // (and never route/scutil — mobileURL is getifaddrs + cached ports).
        // main load is peek only — never CoreImage, never prepareOffMain
        // (WS handleLANChange leftover). Path queue / menu onAppear already
        // prepareOffMain; a bounce from load() raced httpsReady into extra work.
        if Thread.isMainThread {
            return peek(matching: mobileURL())
        }
        let url = mobileURL()
        guard url.hasPrefix("http://") else {
            MagicLog.server("QR: load blocked non-http")
            return nil
        }
        if depth > 3 {
            return peek()
        }
        lock.lock()
        if cachedURL == url, let img = cachedImage {
            pendingURL = nil
            lock.unlock()
            return img
        }
        if generating {
            pendingURL = url
            let img = (cachedURL == url) ? cachedImage : nil
            lock.unlock()
            return img
        }
        generating = true
        pendingURL = nil
        lock.unlock()

        let img = generateQRImage(content: url, pixelSize: 512)
        let live = mobileURL()

        lock.lock()
        generating = false
        let follow = pendingURL
        pendingURL = nil
        var stored: NSImage?
        var published = false
        // Never store a QR whose encoded URL no longer matches live HTTP
        // (LAN moved mid-generate, or httpsReady somehow flipped the string).
        if let img, live == url, live.hasPrefix("http://") {
            published = cachedURL != url || cachedImage == nil
            cachedURL = url
            cachedImage = img
            stored = img
        }
        lock.unlock()

        if published {
            MagicLog.server("QR: dynamic \(url) main=\(Thread.isMainThread)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: readyNotification, object: url)
            }
        }

        if live != url || (follow != nil && follow != url) {
            return load(depth: depth + 1)
        }
        if let stored { return stored }
        MagicLog.server("QR: generate failed for \(url)")
        return peek()
    }

    /// Path monitor / 换网: generate on the caller queue (must be off-main).
    static func prepareOffMain() {
        if Thread.isMainThread {
            DispatchQueue.global(qos: .utility).async { prepareOffMain() }
            return
        }
        _ = load()
    }

    /// 仅当主码 HTTP URL 真的变了才丢缓存。
    /// httpsReady / attachHTTPS 调用这是 no-op（朋友仍扫 :7878，不换成自签 :7879）。
    /// Also no-op when nothing is cached (first generate still in flight) — dumping
    /// nil would make menu onChange(lanIP) call prepareOffMain and log a second QR.
    /// Path / simulate must use `invalidateForLANChange()` (force dump + regenerate).
    static func invalidate(force: Bool = false) {
        let url = mobileURL()
        guard url.hasPrefix("http://") else {
            MagicLog.server("QR: invalidate ignored non-http")
            return
        }
        lock.lock()
        let previous = cachedURL
        if !force, previous == url || (previous == nil && cachedImage == nil) {
            lock.unlock()
            return
        }
        cachedURL = nil
        cachedImage = nil
        pendingURL = url
        lock.unlock()
        MagicLog.server("QR: invalidate \(force ? "force " : "")\(previous ?? "nil") → \(url)")
    }

    /// LAN path / simulate: always dump so prepareOffMain regenerates (even same IP).
    /// httpsReady must keep calling `invalidate()` so the main :7878 code is not rewritten.
    static func invalidateForLANChange() {
        invalidate(force: true)
    }

    private static func generateQRImage(content: String, pixelSize: CGFloat) -> NSImage? {
        guard let data = content.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let extent = output.extent.integral
        guard extent.width > 0, extent.height > 0 else { return nil }
        let scale = pixelSize / extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else {
            let soft = CIContext(options: [.useSoftwareRenderer: true])
            guard let cg2 = soft.createCGImage(scaled, from: scaled.extent) else { return nil }
            return NSImage(cgImage: cg2, size: NSSize(width: pixelSize, height: pixelSize))
        }
        return NSImage(cgImage: cg, size: NSSize(width: pixelSize, height: pixelSize))
    }
}
