// InstallEnvironment.swift
// 只采集「怎么连上」：默认路由网卡、私有 IPv4、空闲端口。
// 不读 SSID / 电脑名 / 家目录；不写进 /health、二维码、日志。

import Darwin
import Foundation

struct InstallSnapshot: Equatable, Sendable {
    let routeIface: String
    let primaryIP: String
    let allIPs: [String]
    let httpPort: UInt16
    let httpsPort: UInt16
    let htmlFromBundle: Bool
    let fingerprint: String

    var httpURL: String { "http://\(primaryIP):\(httpPort)/" }
    var httpsURL: String { "https://\(primaryIP):\(httpsPort)/" }
    /// 主码永远 HTTP :7878。HTTPS 自签不进这里（朋友扫不开）。
    var mobileURL: String { "http://\(primaryIP):\(httpPort)/?auto=1&host=\(primaryIP)" }

    /// Overlay live getifaddrs + route cache onto captured ports.
    /// /health httpUrl/httpsUrl 必须跟当前网卡走，不能停在上次 capture 的 IP。
    func alignedToLiveLAN() -> InstallSnapshot {
        let f = LANDetector.healthFields
        let liveIPs = f.ips.isEmpty ? [f.ip] : f.ips
        if f.routeIface == routeIface, f.ip == primaryIP, liveIPs == allIPs {
            return self
        }
        return InstallSnapshot(
            routeIface: f.routeIface,
            primaryIP: f.ip,
            allIPs: liveIPs,
            httpPort: httpPort,
            httpsPort: httpsPort,
            htmlFromBundle: htmlFromBundle,
            fingerprint: [f.routeIface, f.ip, liveIPs.joined(separator: ","), "\(httpPort)", "\(httpsPort)"].joined(separator: "|")
        )
    }
}

/// /health + menu + QR share this window: live getifaddrs + last captured ports.
struct HealthLAN: Equatable, Sendable {
    let ip: String
    let ips: [String]
    let httpUrl: String
    let httpsUrl: String
    let routeIface: String
    let ifaces: String
    let httpPort: UInt16
    let httpsPort: UInt16

    /// Menu QR / copy-address. Always HTTP :7878. Host is `ip` (live iface).
    var mobileURL: String { "http://\(ip):\(httpPort)/?auto=1&host=\(ip)" }
}

enum InstallEnvironment {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: InstallSnapshot?

    /// 菜单栏 / /health 只读。端口来自上次 capture；IP/网卡每次对齐 LANDetector（getifaddrs，不跑 `route`）。
    /// 禁止在主线程 spawn `route`（会泵 runloop → 和 start() 抢锁，进程假死、7878 起不来）。
    /// Overlay uses the same healthFields window as `healthLAN` (pinned until refreshOffMain).
    /// Never calls liveFallback — /health must not do a second getifaddrs or HTML path lookup.
    /// Reader only: never writes `cached`. Capture is the sole writer so a /health overlay
    /// cannot clobber ports/htmlFromBundle mid handleLANChange.
    static var current: InstallSnapshot {
        let lan = healthLAN
        lock.lock()
        let hit = cached
        lock.unlock()
        if let hit, lan.routeIface == hit.routeIface, lan.ip == hit.primaryIP, lan.ips == hit.allIPs {
            return hit
        }
        return InstallSnapshot(
            routeIface: lan.routeIface,
            primaryIP: lan.ip,
            allIPs: lan.ips,
            httpPort: lan.httpPort,
            httpsPort: lan.httpsPort,
            htmlFromBundle: hit?.htmlFromBundle ?? true,
            fingerprint: [lan.routeIface, lan.ip, lan.ips.joined(separator: ","), "\(lan.httpPort)", "\(lan.httpsPort)"].joined(separator: "|")
        )
    }

    /// Same numbers /health should advertise: ip/ips/httpUrl/httpsUrl/routeIface.
    /// Host always equals LANDetector.ip (live iface), never a build-time IP.
    /// One healthFields window + cached ports — does not call `current` (no second getifaddrs).
    /// httpUrl/httpsUrl host is always `ip` and `ip` is always ips[0].
    /// `routeIface` is the getifaddrs nic that owns `ip` (stale `route` cache cannot linger).
    /// Loopback never appears in ips when a private IPv4 exists.
    /// HTTP workers reuse LANDetector's 8s reader pin so ip and httpUrl stay one host
    /// across AXIsProcessTrusted (WebSocketServer still splits the two reads).
    static var healthLAN: HealthLAN {
        let f = LANDetector.healthFields
        lock.lock()
        let httpPort = cached?.httpPort ?? LANCert.httpPort
        let httpsPort = cached?.httpsPort ?? LANCert.httpsPort
        lock.unlock()
        var ips = f.ips.filter {
            $0 != "127.0.0.1" && !$0.hasPrefix("127.") && !$0.hasPrefix("169.254.")
        }
        if ips.isEmpty {
            ips = [f.ip]
        } else if !ips.contains(f.ip) {
            ips.insert(f.ip, at: 0)
        } else if let idx = ips.firstIndex(of: f.ip), idx != 0 {
            ips.remove(at: idx)
            ips.insert(f.ip, at: 0)
        }
        if ips.count > 8 {
            ips = Array(ips.prefix(8))
        }
        let httpUrl = "http://\(f.ip):\(httpPort)/"
        let httpsUrl = "https://\(f.ip):\(httpsPort)/"
        if ips.first != f.ip || !httpUrl.contains("://\(f.ip):") || !httpsUrl.contains("://\(f.ip):") {
            MagicLog.server("healthLAN mismatch ip=\(f.ip) ips=\(ips) http=\(httpUrl)")
        }
        return HealthLAN(
            ip: f.ip,
            ips: ips,
            httpUrl: httpUrl,
            httpsUrl: httpsUrl,
            routeIface: f.routeIface,
            ifaces: f.ifaces,
            httpPort: httpPort,
            httpsPort: httpsPort
        )
    }

    /// 换网时传入已占用端口，避免把自己正在听的口判成「被占」。
    /// 调用方：start / handleLANChange。不要在 SwiftUI body 里同步 capture。
    /// handleLANChange 在 MainActor：keep 双端口时复用 htmlFromBundle，不做路径查找。
    /// MainActor + keep 双端口 + 尚无 cache：默认 bundle，禁止 resolvedIndexHTMLPath 泵主线程。
    @discardableResult
    static func capture(keepHTTP: UInt16? = nil, keepHTTPS: UInt16? = nil) -> InstallSnapshot {
        var htmlOverride: Bool?
        lock.lock()
        if keepHTTP != nil, keepHTTPS != nil {
            htmlOverride = cached?.htmlFromBundle
            if htmlOverride == nil, Thread.isMainThread {
                htmlOverride = true
            }
        }
        lock.unlock()
        let snap = snapshot(
            keepHTTP: keepHTTP,
            keepHTTPS: keepHTTPS,
            fingerprintTag: nil,
            htmlFromBundleOverride: htmlOverride
        )
        lock.lock()
        cached = snap
        lock.unlock()
        MagicLog.server(
            "env iface=\(snap.routeIface.isEmpty ? "?" : snap.routeIface) " +
            "ips=\(snap.allIPs.count) http=:\(snap.httpPort) https=:\(snap.httpsPort) " +
            "html=\(snap.htmlFromBundle ? "bundle" : "source") main=\(Thread.isMainThread)"
        )
        return snap
    }

    private static func snapshot(
        keepHTTP: UInt16?,
        keepHTTPS: UInt16?,
        fingerprintTag: String?,
        htmlFromBundleOverride: Bool? = nil
    ) -> InstallSnapshot {
        let f = LANDetector.healthFields
        let http = keepHTTP ?? LANCert.httpPort
        let https = keepHTTPS ?? LANCert.httpsPort
        let fromBundle: Bool
        if let htmlFromBundleOverride {
            fromBundle = htmlFromBundleOverride
        } else if Thread.isMainThread {
            // no path lookup on main (resolvedIndexHTMLPath pumps runloop → start/menu freeze)
            fromBundle = true
        } else {
            let html = StaticFileLocator.resolvedIndexHTMLPath() ?? ""
            let bundleHTML = Bundle.main.resourceURL?.appendingPathComponent("index.html").path ?? ""
            fromBundle = !html.isEmpty && (html == bundleHTML || html.contains(".app/Contents/Resources/"))
        }
        let ips = f.ips.isEmpty ? [f.ip] : f.ips
        let fp = fingerprintTag ?? [f.routeIface, f.ip, ips.joined(separator: ","), "\(http)", "\(https)"].joined(separator: "|")
        return InstallSnapshot(
            routeIface: f.routeIface,
            primaryIP: f.ip,
            allIPs: ips,
            httpPort: http,
            httpsPort: https,
            htmlFromBundle: fromBundle,
            fingerprint: fp
        )
    }
}

enum PortProbe {
    static func isFree(_ port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)
        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    static func pick(preferred: UInt16, avoid: UInt16? = nil) -> UInt16 {
        var p = preferred
        for _ in 0..<16 {
            if p != (avoid ?? 0), isFree(p) { return p }
            p &+= 10
        }
        return preferred
    }
}
