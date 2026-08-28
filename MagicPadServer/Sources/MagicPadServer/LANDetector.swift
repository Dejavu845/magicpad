// LANDetector.swift
// 推断本机局域网 IP 和 mDNS 名(用于菜单显示 + QR 编码)
//
// 策略:
//   - IP: 从活跃网络接口收集私有 IPv4；优先 默认路由网卡 → en0 → en1 → 其他 en* → 其余
//   - 多网卡时 allPrivateIPs 供 /health 与菜单展示，避免扫到 Docker/桥接假 IP
//   - mDNS: hostname + "local"
//
// 线程: `ip` / `routeInterface` / `mdns` / `allPrivateIPs` 只读 getifaddrs + 缓存。
// `route` / `scutil` 只允许在 refreshOffMain() 里跑（主线程会泵 runloop → 菜单假死、7878 起不来）。

import Foundation
import Darwin

/// One getifaddrs window: /health ip + ips + httpUrl host + QR host + routeIface.
/// Pinned until path/simulate flush (no clock TTL). No `route`/`scutil` in this snapshot.
struct LANHealth: Equatable, Sendable {
    let ip: String
    let ips: [String]
    let ifaces: String
    let routeIface: String
}

enum LANDetector {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedRouteIface: String = ""
    nonisolated(unsafe) private static var cachedMDNS: String = ""
    /// One getifaddrs window so /health ip + ips + ifaces + QR host cannot disagree.
    /// Lives until refreshOffMain / applyLiveHealth — no clock TTL. Quiet NWPath
    /// must not nil this (AXIsProcessTrusted in /health can exceed 2s).
    nonisolated(unsafe) private static var cachedHealth: LANHealth?
    nonisolated(unsafe) private static var cachedRefreshAt: CFAbsoluteTime = 0
    /// Serializes `route`/`scutil`. Main may bounce here; it must never `sync` wait.
    private static let routeQueue = DispatchQueue(label: "magicpad.lan.route", qos: .utility)
    nonisolated(unsafe) private static var onRouteQueue = false
    /// HTTP-worker pin so /health `ip` (read first) and `httpUrl` (after AX) cannot
    /// split when path/simulate flushes the global pin mid-`AXIsProcessTrusted`.
    /// Main never pins — menu / handleLANChange must see the live window.
    /// Cleared on this thread in refreshOffMain / applyLiveHealth.
    private static let httpReaderPinKey = "magicpad.lan.httpReaderPin"
    private static let httpReaderPinTTL: CFAbsoluteTime = 8

    private final class HTTPReaderPin: NSObject {
        let health: LANHealth
        let at: CFAbsoluteTime
        init(_ health: LANHealth) {
            self.health = health
            self.at = CFAbsoluteTimeGetCurrent()
            super.init()
        }
        var isFresh: Bool { CFAbsoluteTimeGetCurrent() - at < LANDetector.httpReaderPinTTL }
    }

    /// 默认路由网卡名（en1 / en0 …）。多网卡时用它，避免 QR 印到以太网/错网段。
    /// 只读缓存；真正探测见 `refreshOffMain()`。Empty cache → iface of primary from getifaddrs.
    static var routeInterface: String { healthFields.routeIface }

    /// One getifaddrs window so /health ip + ips + ifaces + httpUrl host + QR host cannot disagree.
    /// No clock TTL: AXIsProcessTrusted in /health can exceed 2s; a short TTL split
    /// ip/ips (start of JSON) from httpUrl/httpsUrl (InstallEnvironment.current after AX).
    /// Quiet NWPath must `liveProbe()` without touching this pin. Path / simulate
    /// `refreshOffMain(force:)` swaps the window atomically (never a nil hole).
    /// Primary is always ips[0]. No `route`/`scutil` here.
    /// If `route` has not primed yet, `routeIface` is the getifaddrs name of `ip` (not "").
    /// /health should read `InstallEnvironment.healthLAN` once (same pin) — not
    /// `LANDetector.ip` then `current` after AX. That leftover is WebSocketServer.
    /// HTTP workers keep one window for 8s so that split cannot land; Main never pins.
    static var healthFields: LANHealth {
        if let pin = httpReaderPinIfFresh() {
            return pin
        }
        lock.lock()
        if let hit = cachedHealth {
            lock.unlock()
            storeHTTPReaderPin(hit)
            return hit
        }
        let route = cachedRouteIface
        lock.unlock()

        // First read on MainActor (WS lanIP default / start capture): kick
        // route/scutil off-main. This return still uses getifaddrs ranking so
        // /health never waits. Dual-home picks the default nic once primed.
        if route.isEmpty, Thread.isMainThread {
            refreshOffMain(force: true)
        }

        let result = makeHealth(routeIface: route)
        lock.lock()
        if let hit = cachedHealth {
            lock.unlock()
            storeHTTPReaderPin(hit)
            return hit
        }
        cachedHealth = result
        lock.unlock()
        storeHTTPReaderPin(result)
        return result
    }

    /// Non-main /health only. Main never pins.
    private static func httpReaderPinIfFresh() -> LANHealth? {
        if Thread.isMainThread { return nil }
        guard let pin = Thread.current.threadDictionary[httpReaderPinKey] as? HTTPReaderPin,
              pin.isFresh else { return nil }
        return pin.health
    }

    private static func storeHTTPReaderPin(_ health: LANHealth) {
        if Thread.isMainThread { return }
        Thread.current.threadDictionary[httpReaderPinKey] = HTTPReaderPin(health)
    }

    private static func clearHTTPReaderPin() {
        Thread.current.threadDictionary.removeObject(forKey: httpReaderPinKey)
    }

    /// Uncached getifaddrs snapshot. No `route`/`scutil`. Does not touch the /health pin.
    /// Path-queue quiet compare: if `liveProbe().ip` equals last primary, skip refresh.
    static func liveProbe() -> LANHealth {
        lock.lock()
        let route = cachedRouteIface
        lock.unlock()
        return makeHealth(routeIface: route)
    }

    /// Replace the pin with a live getifaddrs window (no nil hole, no `route`/`scutil`).
    /// Path / simulate only. Not /health.
    static func flushIfaddrsCache() {
        applyLiveHealth()
    }

    /// Atomic swap: probe then store. Readers see old or new, never a torn nil rebuild.
    @discardableResult
    private static func applyLiveHealth(routeIface: String? = nil) -> LANHealth {
        clearHTTPReaderPin()
        lock.lock()
        let route = routeIface ?? cachedRouteIface
        lock.unlock()
        let next = makeHealth(routeIface: route)
        lock.lock()
        cachedHealth = next
        lock.unlock()
        storeHTTPReaderPin(next)
        return next
    }

    /// Build ip/ips/ifaces/routeIface from one getifaddrs pass. No process spawn.
    /// Advertised `routeIface` always owns `ip` (stale `route` cache cannot point at a down nic).
    private static func makeHealth(routeIface: String) -> LANHealth {
        let all = probeNamedPrivateIPv4()
        let routeAlive = !routeIface.isEmpty && all.contains(where: { $0.name == routeIface })
        let pickFrom = routeAlive ? routeIface : ""
        let primary = pickPrimary(from: all, routeIface: pickFrom)
        var iface = pickFrom
        if let hit = all.first(where: { $0.ip == primary }) {
            iface = hit.name
        }
        var ips: [String] = []
        var seen = Set<String>()
        for item in all {
            if item.ip.hasPrefix("127.") || item.ip.hasPrefix("169.254.") { continue }
            if seen.insert(item.ip).inserted {
                ips.append(item.ip)
            }
        }
        if !seen.contains(primary) {
            ips.insert(primary, at: 0)
        } else if let idx = ips.firstIndex(of: primary), idx != 0 {
            ips.remove(at: idx)
            ips.insert(primary, at: 0)
        }
        // health cap 8 — /health ips/ifaces contract (primary stays ips[0])
        if ips.count > 8 {
            ips = Array(ips.prefix(8))
        }
        var ifacePairs = all
            .filter { !$0.ip.hasPrefix("127.") && !$0.ip.hasPrefix("169.254.") }
            .map { "\($0.name)=\($0.ip)" }
        if ifacePairs.count > 8 {
            let advertised = "\(iface)=\(primary)"
            if ifacePairs.prefix(8).contains(advertised) {
                ifacePairs = Array(ifacePairs.prefix(8))
            } else {
                ifacePairs = [advertised] + Array(ifacePairs.filter { $0 != advertised }.prefix(7))
            }
        }
        let ifaces = ifacePairs.joined(separator: ",")
        return LANHealth(ip: primary, ips: ips, ifaces: ifaces, routeIface: iface)
    }

    /// 首选局域网 IPv4：缓存的默认路由网卡 → en0 → en1 → 其他 en* → 其余
    /// 不 spawn `route`/`scutil`。无缓存时按 en* 排名，等 refreshOffMain 校准。
    static var ip: String { healthFields.ip }

    /// 手机扫码 URL。永远 HTTP（朋友/新设备要能打开 :7878）。HTTPS 自签不进主码。
    static func mobileHTTPURL(port: UInt16) -> String {
        let live = healthFields.ip
        return "http://\(live):\(port)/?auto=1&host=\(live)"
    }

    /// 所有私有 IPv4。Primary (`ip`) is always present and first.
    static var allPrivateIPs: [String] { healthFields.ips }

    /// 调试用：iface=ip 列表
    static var interfaceSummary: String { healthFields.ifaces }

    /// mDNS 名(去 .local 后缀)。只读缓存；scutil 在 refreshOffMain。
    static var mdns: String {
        lock.lock()
        let cached = cachedMDNS
        lock.unlock()
        if isUsableHostLabel(cached) { return cached }
        let name = ProcessInfo.processInfo.hostName
            .components(separatedBy: ".").first ?? "mac"
        let lower = name.lowercased()
        return isUsableHostLabel(lower) ? lower : "mac"
    }

    /// Off-main only. Runs `/sbin/route -n get default` + `scutil`.
    /// Path monitor / 换网必须走这里，禁止在 MainActor 里 waitUntilExit.
    /// `force`: prime / simulate / real IP move. Quiet-LAN callers omit it —
    /// a 3s cooldown skips `route`/`scutil` when the cached iface is still up.
    /// Main-thread callers bounce onto `magicpad.lan.route` (never sync — that froze the menu).
    /// Path / simulate `sync` onto that queue so two `route` processes cannot stack.
    static func refreshOffMain(force: Bool = false) {
        if Thread.isMainThread {
            MagicLog.server("LANDetector.refreshOffMain bounced off main thread")
            routeQueue.async {
                runOnRouteQueue(force: force)
            }
            return
        }
        lock.lock()
        let nested = onRouteQueue
        lock.unlock()
        if nested {
            refreshOffMainBody(force: force)
            return
        }
        routeQueue.sync {
            runOnRouteQueue(force: force)
        }
    }

    private static func runOnRouteQueue(force: Bool) {
        lock.lock()
        onRouteQueue = true
        lock.unlock()
        defer {
            lock.lock()
            onRouteQueue = false
            lock.unlock()
        }
        refreshOffMainBody(force: force)
    }

    private static func refreshOffMainBody(force: Bool) {
        if Thread.isMainThread {
            MagicLog.server("LANDetector.refreshOffMainBody refused on main")
            return
        }
        clearHTTPReaderPin()
        if !force {
            lock.lock()
            let previousIface = cachedRouteIface
            let previousAt = cachedRefreshAt
            lock.unlock()
            if !previousIface.isEmpty, previousAt > 0,
               CFAbsoluteTimeGetCurrent() - previousAt < 3 {
                let all = probeNamedPrivateIPv4()
                if all.contains(where: { $0.name == previousIface }) {
                    // Skip route/scutil; still pin a live getifaddrs window (DHCP on same nic).
                    _ = applyLiveHealth(routeIface: previousIface)
                    return
                }
            }
        }
        let iface = readDefaultRouteInterface() ?? ""
        let bonjour = readMDNS()
        let next = makeHealth(routeIface: iface)
        lock.lock()
        cachedRouteIface = iface
        cachedMDNS = bonjour
        cachedHealth = next
        cachedRefreshAt = CFAbsoluteTimeGetCurrent()
        lock.unlock()
        MagicLog.server(
            "LANDetector refresh off-main iface=\(iface.isEmpty ? "?" : iface) ip=\(next.ip) main=\(Thread.isMainThread)"
        )
    }

    private static func pickPrimary(from all: [NamedIP], routeIface: String) -> String {
        if !routeIface.isEmpty,
           let hit = all.first(where: { $0.name == routeIface }) {
            return hit.ip
        }
        if let en0 = all.first(where: { $0.name == "en0" }) { return en0.ip }
        if let en1 = all.first(where: { $0.name == "en1" }) { return en1.ip }
        if let en = all.first(where: { $0.name.hasPrefix("en") }) { return en.ip }
        return all.first?.ip ?? "127.0.0.1"
    }

    private static func isUsableHostLabel(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return false }
        if s.allSatisfy({ $0.isNumber || $0 == "." }) { return false }
        return true
    }

    private static func readMDNS() -> String {
        if let bonjour = scutilName("LocalHostName"), isUsableHostLabel(bonjour) {
            return bonjour.lowercased()
        }
        if let computer = scutilName("ComputerName"), isUsableHostLabel(computer) {
            return computer.lowercased()
                .replacingOccurrences(of: " ", with: "-")
        }
        let name = ProcessInfo.processInfo.hostName
            .components(separatedBy: ".").first ?? "mac"
        let lower = name.lowercased()
        return isUsableHostLabel(lower) ? lower : "mac"
    }

    private static func scutilName(_ key: String) -> String? {
        let text = runTool(
            path: "/usr/sbin/scutil",
            arguments: ["--get", key]
        )
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private static func isPrivate(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 127 { return false }
        if parts[0] == 169 && parts[1] == 254 { return false }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 10 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        return false
    }

    private struct NamedIP {
        let name: String
        let ip: String
    }

    /// 活跃非 loopback 私有 IPv4 + 接口名；排序 en0 > en1 > en* > 其他.
    /// Window lives on `healthFields` (pinned until refreshOffMain), not a second list cache.
    private static func probeNamedPrivateIPv4() -> [NamedIP] {
        var found: [NamedIP] = []

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while ptr != nil {
            let interface = ptr!.pointee
            let flags = interface.ifa_flags
            let addr = interface.ifa_addr

            if (flags & UInt32(IFF_UP)) == 0 || (flags & UInt32(IFF_LOOPBACK)) != 0 {
                ptr = interface.ifa_next
                continue
            }

            if addr?.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // 跳过虚拟/链路本地辅助接口
                if name.hasPrefix("lo")
                    || name.hasPrefix("awdl")
                    || name.hasPrefix("llw")
                    || name.hasPrefix("utun")
                    || name.hasPrefix("bridge")
                    || name.hasPrefix("veth")
                    || name.hasPrefix("docker")
                    || name.hasPrefix("vmnet")
                    || name.hasPrefix("ap") {
                    ptr = interface.ifa_next
                    continue
                }
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr!.pointee.sa_len),
                              &hostname, socklen_t(hostname.count),
                              nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostname)
                    if !ip.isEmpty
                        && ip != "127.0.0.1"
                        && !ip.hasPrefix("127.")
                        && !ip.hasPrefix("169.254.")
                        && isPrivate(ip) {
                        found.append(NamedIP(name: name, ip: ip))
                    }
                }
            }
            ptr = interface.ifa_next
        }

        return found.sorted { a, b in
            rank(a.name) < rank(b.name)
        }
    }

    /// `route -n get default` → interface: en1. Caller must be off-main.
    private static func readDefaultRouteInterface() -> String? {
        guard let text = runTool(
            path: "/sbin/route",
            arguments: ["-n", "get", "default"]
        ) else { return nil }
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("interface:") {
                let name = line.dropFirst("interface:".count).trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : name
            }
        }
        return nil
    }

    private static func runTool(path: String, arguments: [String], timeout: TimeInterval = 2) -> String? {
        if Thread.isMainThread {
            MagicLog.server("LANDetector.runTool refused on main \(path)")
            return nil
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        let sem = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in sem.signal() }
        do {
            try task.run()
        } catch {
            return nil
        }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            _ = sem.wait(timeout: .now() + 0.4)
            MagicLog.server("LANDetector \(path) timeout \(Int(timeout))s off-main")
            return nil
        }
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func rank(_ name: String) -> Int {
        if name == "en0" { return 0 }
        if name == "en1" { return 1 }
        if name.hasPrefix("en") { return 2 }
        return 10
    }
}
