// LANNetworkMonitor.swift
// Watch NWPath for Wi‑Fi / interface changes (leave home SSID, DHCP renumber).
// On change: refresh LANDetector off-main (route/scutil), then handleLANChange on main.
// No product LLM. No Continuity/BT.

import Foundation
import Network

final class LANNetworkMonitor: @unchecked Sendable {
    static let shared = LANNetworkMonitor()

    /// Overnight / debug: `notifyutil -p app.magicpad.lan.simulate` (never on the HTTP QR).
    static let simulateNotifyName = "app.magicpad.lan.simulate"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "magicpad.lan.path", qos: .utility)
    private let lock = NSLock()
    private var started = false
    private var lastPrimaryIP: String = ""
    private var lastIfaceSummary: String = ""
    /// NWPath `availableInterfaces[0]` — dual-home default-route hint (not a `route` spawn).
    private var lastPathPreferred: String = ""
    private var debounceWork: DispatchWorkItem?
    private var simulateHookInstalled = false

    private init() {}

    func start() {
        lock.lock()
        if started {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            // Already on `queue`. Do not hop to MainActor before route/scutil.
            self?.scheduleHandle(path: path)
        }
        monitor.start(queue: queue)
        queue.async { [weak self] in
            self?.primeInitial()
        }
        installSimulateHook()
        MagicLog.server("LAN path monitor started (route/scutil off-main)")
    }

    func stop() {
        lock.lock()
        guard started else {
            lock.unlock()
            return
        }
        started = false
        debounceWork?.cancel()
        debounceWork = nil
        lock.unlock()
        removeSimulateHook()
        monitor.cancel()
        MagicLog.server("LAN path monitor stopped")
    }

    /// Overnight step 4: same off-main path as a real NWPath event.
    /// Does not block the caller (main-thread safe). route/scutil stay on `queue`.
    func simulateLANChange(reason: String = "simulate") {
        MagicLog.server("LAN simulate requested main=\(Thread.isMainThread) → path queue")
        queue.async { [weak self] in
            let t0 = CFAbsoluteTimeGetCurrent()
            self?.publishIfNeeded(reason: reason, force: true, pathPreferred: nil)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            MagicLog.server("LAN simulate done ms=\(ms) main=\(Thread.isMainThread)")
        }
    }

    private func installSimulateHook() {
        lock.lock()
        if simulateHookInstalled {
            lock.unlock()
            return
        }
        simulateHookInstalled = true
        lock.unlock()
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            ptr,
            { _, _, _, _, _ in
                LANNetworkMonitor.shared.simulateLANChange(reason: "darwin-notify")
            },
            Self.simulateNotifyName as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func removeSimulateHook() {
        lock.lock()
        guard simulateHookInstalled else {
            lock.unlock()
            return
        }
        simulateHookInstalled = false
        lock.unlock()
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    /// Seed route cache without calling handleLANChange (HTTPS may still be attaching).
    /// capture stays on this path queue — start() already captured ports; this only
    /// overlays live getifaddrs. Never wait on route/scutil from MainActor.
    private func primeInitial() {
        if Thread.isMainThread {
            queue.async { [weak self] in self?.primeInitial() }
            return
        }
        LANDetector.refreshOffMain(force: true)
        let snap = InstallEnvironment.current
        _ = InstallEnvironment.capture(
            keepHTTP: snap.httpPort,
            keepHTTPS: snap.httpsPort
        )
        QRImageLoader.prepareOffMain()
        let live = LANDetector.healthFields
        lock.lock()
        lastPrimaryIP = live.ip
        lastIfaceSummary = live.ifaces
        lastPathPreferred = ""
        lock.unlock()
        MagicLog.server("LAN path primed off-main primary=\(live.ip) ifaces=\(live.ifaces) main=\(Thread.isMainThread)")
        Task { @MainActor in
            _ = QRImageLoader.peek()
        }
    }

    /// Debounce flapping (roam / brief unsatisfied) ~0.8s on the path queue.
    private func scheduleHandle(path: NWPath) {
        lock.lock()
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.handle(path: path)
        }
        debounceWork = work
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func handle(path: NWPath) {
        if Thread.isMainThread {
            MagicLog.server("LAN handle refused on main — bouncing to path queue")
            queue.async { [weak self] in self?.handle(path: path) }
            return
        }
        let status: String
        switch path.status {
        case .satisfied: status = "satisfied"
        case .unsatisfied: status = "unsatisfied"
        case .requiresConnection: status = "requiresConnection"
        @unknown default: status = "unknown"
        }
        // Never force on flap: unsatisfied with the same getifaddrs IP and the same
        // preferred nic is a no-op. Dual-home default-route switch: first available
        // iface changes even if both IPs stay up — that hint runs `route` off-main.
        // simulateLANChange(force: true) still runs route/scutil + handleLANChange.
        let preferred = path.availableInterfaces.first?.name ?? ""
        publishIfNeeded(reason: status, force: false, pathPreferred: preferred)
    }

    private func publishIfNeeded(reason: String, force: Bool, pathPreferred: String?) {
        if Thread.isMainThread {
            MagicLog.server("LAN publish bounced off main")
            queue.async { [weak self] in
                self?.publishIfNeeded(reason: reason, force: force, pathPreferred: pathPreferred)
            }
            return
        }

        // Fast path: uncached getifaddrs only. Skip `route`/`scutil` + handleLANChange
        // when the QR host (primary IP) did not move AND NWPath preferred iface is
        // unchanged. Do **not** flush the /health pin on that quiet path — a blip
        // during AXIsProcessTrusted would split ip from httpUrl.
        let live = LANDetector.liveProbe()
        lock.lock()
        let running = started
        let ipChanged = live.ip != lastPrimaryIP
        let ifaceChanged = live.ifaces != lastIfaceSummary
        // First NWPath after prime: lastPathPreferred is empty — adopt, don't extra `route`.
        let preferredChanged: Bool
        if let pref = pathPreferred, !lastPathPreferred.isEmpty {
            preferredChanged = pref != lastPathPreferred
        } else {
            preferredChanged = false
        }
        lock.unlock()
        guard running else { return }
        if !force && !ipChanged && !preferredChanged {
            lock.lock()
            if ifaceChanged {
                lastIfaceSummary = live.ifaces
            }
            if let pathPreferred, lastPathPreferred.isEmpty {
                lastPathPreferred = pathPreferred
            }
            lock.unlock()
            return
        }

        LANDetector.refreshOffMain(force: true)
        let after = LANDetector.healthFields
        lock.lock()
        let previousIP = lastPrimaryIP
        let previousIfaces = lastIfaceSummary
        lastPrimaryIP = after.ip
        lastIfaceSummary = after.ifaces
        if let pathPreferred {
            lastPathPreferred = pathPreferred
        }
        let hostMoved = previousIP != after.ip
        lock.unlock()

        if !force && !hostMoved {
            MagicLog.server(
                "LAN path \(reason) route reconfirmed ip=\(after.ip) preferred=\(pathPreferred ?? "-") off-main=\(!Thread.isMainThread)"
            )
            return
        }

        MagicLog.server(
            "LAN path \(reason) ip \(previousIP)→\(after.ip) ifaces \(previousIfaces)→\(after.ifaces) off-main=\(!Thread.isMainThread) force=\(force)"
        )

        // Capture off-main (keep ports) so handleLANChange on MainActor is a
        // cache hit: no resolvedIndexHTMLPath, no route/scutil. QR + /health
        // overlay then share one window. Quiet path above must not capture.
        // route/scutil already ran in refreshOffMain on this queue — never on main.
        let ports = InstallEnvironment.current
        _ = InstallEnvironment.capture(keepHTTP: ports.httpPort, keepHTTPS: ports.httpsPort)

        // Force dump + CoreImage on this path queue, then hop. handleLANChange on
        // main only cache-hits (load() is peek-only there). httpsReady still
        // calls invalidate() (no force) so the main HTTP :7878 QR is not rewritten
        // when TLS comes up.
        QRImageLoader.invalidateForLANChange()
        QRImageLoader.prepareOffMain()
        let lan = InstallEnvironment.healthLAN
        let qr = QRImageLoader.mobileURL(from: lan)
        MagicLog.server("LAN QR after \(reason) url=\(qr) http=\(qr.hasPrefix("http://")) main=\(Thread.isMainThread)")

        Task { @MainActor in
            _ = QRImageLoader.peek()
            WebSocketServer.shared.handleLANChange(
                primaryIP: after.ip,
                pathStatus: reason
            )
        }
    }
}
