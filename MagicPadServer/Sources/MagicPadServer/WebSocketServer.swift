// WebSocketServer.swift
// 最小 WebSocket server 实现(rfc6455 子集)
//
// 特性:
//   - 基于 Network.framework 的 NWListener
//   - TCP_NODELAY 已开
//   - 支持 binary(0x2) + text(0x1) 帧
//   - 不支持分片(fragmentation,MVP 不需要)
//   - 应用层 ping/pong（JSON）；hello → hello_ack{htmlRev,ax,clients}
//
// 用法:
//   await WebSocketServer.shared.start(port: 7878)
//   WebSocketServer.shared.onMessage = { ... }
//   await WebSocketServer.shared.stop()
//
// 公开状态(@MainActor 暴露给 SwiftUI 菜单):
//   @Published var isRunning
//   @Published var clientCount
//   @Published var lastEventSummary

import Foundation
import Network
import AppKit
import ApplicationServices  // AXIsProcessTrusted for /health
import MagicPadCore

// MARK: - 公共状态(给 SwiftUI 菜单观察)

@MainActor
final class WebSocketServer: ObservableObject {
    static let shared = WebSocketServer()

    @Published private(set) var isRunning = false
    @Published private(set) var httpsReady = false
    @Published private(set) var clientCount: Int = 0
    /// H779: /health 在 WSConnection 线程读，不碰 MainActor
    nonisolated(unsafe) static var liveClientCount: Int = 0
    @Published private(set) var lastEventSummary: String = "—"
    /// Live primary LAN IPv4 (menu / QR refresh on leave-home Wi‑Fi)
    @Published private(set) var lanIP: String = LANDetector.ip
    @Published private(set) var lanIPs: [String] = LANDetector.allPrivateIPs

    /// 收到消息时回调(actor 内,可做实际事件处理)
    var onMessage: ((Message) -> Void)?

    enum Message {
        case text(String)
        case binary(Data)
        case close
    }

    /// HTTP :7878 + optional HTTPS :7879 (LAN self-signed)
    private var listeners: [NWListener] = []
    private var connections: [ObjectIdentifier: WSConnection] = [:]
    private var boundHTTPPort: UInt16 = LANCert.httpPort
    private var boundHTTPSPort: UInt16 = LANCert.httpsPort
    private var lanChangeBusy = false

    private init() {}

    // MARK: - 生命周期

    func start(port: UInt16 = LANCert.httpPort, httpsPort: UInt16 = LANCert.httpsPort, keepPorts: Bool = false) {
        guard listeners.isEmpty else {
            MagicLog.server("已经在跑,无需重复 start")
            return
        }

        // H781: 默认永远 7878/7879。PortProbe 跳到 7888 会让手机收藏夹全失效。
        _ = InstallEnvironment.capture(
            keepHTTP: keepPorts ? port : LANCert.httpPort,
            keepHTTPS: keepPorts ? httpsPort : LANCert.httpsPort
        )
        boundHTTPPort = keepPorts ? port : LANCert.httpPort
        boundHTTPSPort = keepPorts ? httpsPort : LANCert.httpsPort
        if boundHTTPPort != LANCert.httpPort || boundHTTPSPort != LANCert.httpsPort {
            MagicLog.server("env deploy ports http=:\(boundHTTPPort) https=:\(boundHTTPSPort)")
        }
        refreshPublishedLAN()

        var started = 0
        var summaryBits: [String] = []

        // 1) Plain HTTP + WS first (must not block on cert/keychain)
        if attachListener(port: boundHTTPPort, parameters: LANCert.plainTCPParameters(), label: "http") {
            started += 1
            summaryBits.append("http:\(boundHTTPPort)")
        }

        if started > 0 {
            isRunning = true
            lastEventSummary = "已启动 " + summaryBits.joined(separator: " · ")
            LANNetworkMonitor.shared.start()
        } else {
            isRunning = false
            httpsReady = false
            lastEventSummary = "启动失败: 无可用端口"
            MagicLog.server("start failed: no listeners")
            return
        }

        // 2) HTTPS off MainActor: openssl/SecPKCS12 must not freeze menu / HTTP accept
        attachHTTPSAsync(port: boundHTTPSPort, httpPort: boundHTTPPort)
        // H784: 权重预拉，不占 ANE。第一次听写就能直接说。
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4) {
            LocalWhisper.shared.prefetchWeights()
        }
    }

    private func attachHTTPSAsync(port: UInt16, httpPort: UInt16) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Ensure SAN covers current LAN before building TLS params
            _ = LANCert.revalidateForCurrentLAN()
            let tlsParams = LANCert.makeTLSParameters()
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isRunning else { return }
                if let tlsParams {
                    if self.attachListener(port: port, parameters: tlsParams, label: "https") {
                        self.httpsReady = true
                        self.lastEventSummary = "已启动 http:\(httpPort) · https:\(port)"
                        MagicLog.server("HTTPS ready :\(port)")
                    } else {
                        self.httpsReady = false
                        MagicLog.server("HTTPS listener attach failed :\(port)")
                    }
                } else {
                    self.httpsReady = false
                    let why = LANCert.statusError.isEmpty ? "no cert" : LANCert.statusError
                    MagicLog.server("HTTPS skipped: \(why)")
                }
                self.refreshPublishedLAN()
                QRImageLoader.invalidate()
            }
        }
    }

    private func refreshPublishedLAN() {
        lanIP = LANDetector.ip
        lanIPs = LANDetector.allPrivateIPs
    }

    /// Called by LANNetworkMonitor after Wi‑Fi / path change (debounced).
    func handleLANChange(primaryIP: String, pathStatus: String) {
        _ = InstallEnvironment.capture(keepHTTP: boundHTTPPort, keepHTTPS: boundHTTPSPort)
        refreshPublishedLAN()
        QRImageLoader.invalidate()
        _ = QRImageLoader.load()

        guard isRunning else { return }
        guard !lanChangeBusy else {
            MagicLog.server("LAN change skipped (busy) ip=\(primaryIP) status=\(pathStatus)")
            return
        }
        lanChangeBusy = true
        lastEventSummary = "网络变更 \(primaryIP) · \(pathStatus)"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let regenerated = LANCert.revalidateForCurrentLAN()
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.lanChangeBusy = false }
                self.refreshPublishedLAN()
                QRImageLoader.invalidate()
                if regenerated || !self.httpsReady {
                    MagicLog.server("LAN change → restart HTTPS (regen=\(regenerated))")
                    self.restartHTTPSOnly()
                } else {
                    MagicLog.server("LAN change → SAN OK, keep listeners ip=\(self.lanIP)")
                    self.lastEventSummary = "运行中 · \(self.lanIP)"
                }
            }
        }
    }

    /// Full restart after cert regen / path change (ports unchanged; brief blip).
    private func restartHTTPSOnly() {
        let http = boundHTTPPort
        let https = boundHTTPSPort
        stop(keepMonitor: true)
        // Allow TIME_WAIT / NWListener teardown before rebind
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            guard self.listeners.isEmpty else { return }
            self.start(port: http, httpsPort: https, keepPorts: true)
        }
    }

    /// Create + start one NWListener; appends to `listeners` on success.
    @discardableResult
    private func attachListener(port: UInt16, parameters: NWParameters, label: String) -> Bool {
        do {
            let nwPort = NWEndpoint.Port(rawValue: port)!
            let listener = try NWListener(using: parameters, on: nwPort)
            listeners.append(listener)

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    MagicLog.server("listening \(label) on [::]:\(port) (IPv4-mapped + IPv6)")
                case .failed(let err):
                    MagicLog.server("listener \(label) failed: \(err)")
                case .cancelled:
                    MagicLog.server("listener \(label) cancelled")
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor [weak self] in
                    self?.accept(conn)
                }
            }

            listener.start(queue: .global(qos: .userInitiated))
            return true
        } catch {
            MagicLog.server("start \(label) :\(port) failed: \(error)")
            return false
        }
    }

    func stop(keepMonitor: Bool = false) {
        if !keepMonitor {
            LANNetworkMonitor.shared.stop()
        }
        for listener in listeners {
            listener.cancel()
        }
        listeners.removeAll()
        for conn in connections.values {
            conn.close()
        }
        connections.removeAll()
        isRunning = false
        httpsReady = false
        clientCount = 0
        Self.liveClientCount = 0
        lastEventSummary = "已停止"
        MagicLog.server("stopped")
    }

    // MARK: - 接受新连接

    private func accept(_ conn: NWConnection) {
        let ws = WSConnection(connection: conn)
        let id = ObjectIdentifier(ws)
        connections[id] = ws
        clientCount = connections.count
        Self.liveClientCount = clientCount
        MagicLog.ws("new connection from \(conn.endpoint)")
        ws.onText = { [weak self] text in
            // FIFO hop. Task { @MainActor } is not ordered — type then ⌫ could
            // swap before injectQueue. main.async is serial (same as key acks).
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.handleText(text, from: id)
                }
            }
        }
        ws.onBinary = { [weak self] data in
            // H12: echo on the WS receive thread (userInteractive). Do not wait for MainActor.
            if data.count >= 13 {
                let tMs = UInt32(data[7]) | (UInt32(data[8]) << 8) | (UInt32(data[9]) << 16) | (UInt32(data[10]) << 24)
                let seq = UInt16(data[11]) | (UInt16(data[12]) << 8)
                ws.sendLatencyEcho(seq: seq, tMs: tMs)
            }
            InjectRuntime.async {
                EventInjector.consumeBinaryFrame(data)
            }
            // Menu summary only — skip hop on move/scroll (every-frame MainActor was the lag)
            if data.count >= 1 {
                let phase = data[0]
                if phase != 1 && phase != 20 {
                    Task { @MainActor [weak self] in
                        self?.noteBinaryUI(data)
                    }
                }
            }
        }
        ws.onClose = { [weak self] in
            Task { @MainActor [weak self] in
                self?.removeConnection(id)
            }
        }
        ws.start()
    }

    private func removeConnection(_ id: ObjectIdentifier) {
        connections.removeValue(forKey: id)
        clientCount = connections.count
        Self.liveClientCount = clientCount
        MagicLog.ws("connection closed, remaining=\(clientCount)")
        // 断线时松键：防止手机杀后台后 Mac 仍 leftMouseDown → 滑着选字
        let rem = clientCount
        InjectRuntime.async {
            EventInjector.releaseStuckButtons(reason: "ws-disconnect rem=\(rem)")
        }
    }

    private func handleText(_ text: String, from id: ObjectIdentifier) {
        MagicLog.event("text (\(text.count)B): \(text.prefix(200))")
        lastEventSummary = "text \(text.count)B @ \(timestamp())"
        onMessage?(.text(text))

        // 文本协议:
        //   key:   { "type":"key", "action":"backspace|clearField|selectAll|left|..." }
        if text.hasPrefix("{") {
            handleJSONText(text, from: id)
        }
    }

    private func handleJSONText(_ text: String, from id: ObjectIdentifier) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "voice":
            handleVoiceText(json, from: id)
        case "key":
            handleKeyAction(json, from: id)
        case "type", "text":
            handleTypeText(json, from: id)
        case "stt":
            handleSTTControl(json, from: id)
        case "hello":
            // H777: 空闲 stuck 键才松（拖选中 bumpResumePing 也会 hello）
            InjectRuntime.async {
                EventInjector.releaseIdleStuckButtons(reason: "hello")
            }
            let rev = StaticFileLocator.htmlRev()
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let axNow = AXIsProcessTrusted()
            let n = connections.count
            connections[id]?.sendText("{\"type\":\"hello_ack\",\"ok\":true,\"ts\":\(Int(Date().timeIntervalSince1970)),\"htmlRev\":\"\(rev)\",\"ax\":\(axNow ? "true" : "false"),\"clients\":\(n)}")
            MagicLog.event("hello from client clients=\(n)")
        case "ping":
            // 应用层心跳（非 RFC6455 opcode ping）— 多设备静置后保持路径可观测
            let t = json["ts"] as? Double ?? 0
            connections[id]?.sendText("{\"type\":\"pong\",\"ts\":\(t),\"serverTs\":\(Int(Date().timeIntervalSince1970 * 1000))}")
        case "classify":
            // H2-1: client two-finger verdict telemetry — no CGEvent inject
            handleClassify(json, from: id)
        default:
            break
        }
    }

    /// H2-1: two-finger classify telemetry. Never injects. Smoke + HUD only.
    private func handleClassify(_ json: [String: Any], from id: ObjectIdentifier) {
        let kind = (json["kind"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = (json["reason"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kind.isEmpty else { return }
        let phase: Int
        if let n = json["phase"] as? NSNumber {
            phase = n.intValue
        } else if let n = json["phase"] as? Int {
            phase = n
        } else {
            phase = 0
        }
        GestureTelemetry.note(kind: kind, reason: reason.isEmpty ? "classify" : reason, phase: phase)
        let ack: [String: Any] = [
            "type": "classify_ack",
            "ok": true,
            "kind": String(kind.prefix(32)),
            "reason": String(reason.prefix(64)),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: ack),
           let text = String(data: data, encoding: .utf8) {
            connections[id]?.sendText(text)
        }
    }

    /// P2-1: Mac 麦克风 STT 控制（手机触发，Mac 听写，结果回手机，仍无 LLM）
    private func handleSTTControl(_ json: [String: Any], from id: ObjectIdentifier) {
        let action = (json["action"] as? String ?? "").lowercased()
        let lang = json["lang"] as? String
        let preferOnDevice = (json["onDevice"] as? Bool) ?? true

        // Broadcast STT events to all clients (usually one phone).
        // SpeechSession is not MainActor; hop for @Published WebSocketServer state.
        SpeechSession.shared.onEvent = { [weak self] payload in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for conn in self.connections.values {
                    conn.sendText(payload)
                }
                self.lastEventSummary = "stt @ \(self.timestamp())"
            }
        }

        switch action {
        case "start", "begin", "on":
            SpeechSession.shared.start(lang: lang, preferOnDevice: preferOnDevice)
            lastEventSummary = "stt start @ \(timestamp())"
        case "stop", "end", "off":
            SpeechSession.shared.stop()
            lastEventSummary = "stt stop @ \(timestamp())"
        case "status":
            SpeechSession.shared.refreshAuthStatus()
            let s = SpeechSession.shared
            let payload: [String: Any] = [
                "type": "stt_status",
                "state": s.isListening ? "listening" : "idle",
                "auth": s.authSpeech,
                "onDeviceSupported": s.supportsOnDevice,
                "lang": lang ?? "zh-CN",
                "whisperReady": LocalWhisper.shared.isReady,
                "whisperModel": LocalWhisper.modelVariant,
                "engine": LocalWhisper.shared.isReady ? "whisper" : "apple",
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let str = String(data: data, encoding: .utf8) {
                connections[id]?.sendText(str)
            }
        default:
            connections[id]?.sendText(
                "{\"type\":\"stt_final\",\"ok\":false,\"reason\":\"bad_action\",\"text\":\"\"}"
            )
        }
    }

    /// iPhone 键盘直达 Mac 焦点：{ "type":"type", "text":"任意内容" }
    /// Text parsed via pure `KeyProtocol.parseType` (missing/null→empty_type; non-string→bad_type; max 2000).
    private func handleTypeText(_ json: [String: Any], from id: ObjectIdentifier) {
        let clamped = KeyProtocol.parseType(from: json)
        guard !clamped.empty else {
            // empty_type | bad_type — no inject, do not clear last payload
            InjectTelemetry.note("type \(clamped.reason)", ok: false, reason: clamped.reason)
            sendVoiceAck(to: id, ok: false, reason: clamped.reason)
            return
        }
        let text = clamped.text
        let successReason = clamped.reason // "type" | "type_truncated"
        let truncated = clamped.truncated
        // Stage before AX/clipboard so ax_denied cannot drop server-side text.
        let gen = LastTextPayload.remember(text)
        // AX off: clipboard on MainActor now (same as voice). Do not hop after
        // injectQueue — that let a later voice overwrite this type, and dropped
        // the ack reason to hard ax_denied if the hop lost the string.
        if !EventInjector.hasAccessibilityPermission {
            let delivered = EventInjector.clipboardFallbackKeepingPayload(text)
            InjectTelemetry.note(
                delivered.ok ? "type clipboard" : "type clipboard_fail",
                ok: delivered.ok,
                reason: delivered.reason
            )
            MagicLog.event("type \(text.count)B truncated=\(truncated) ok=\(delivered.ok) reason=\(delivered.reason)")
            sendVoiceAck(to: id, ok: delivered.ok, reason: delivered.reason)
            lastEventSummary = "type \(text.count)\(truncated ? " trunc" : "") @ \(timestamp())"
            return
        }
        // Same injectQueue as ⌫ — unicode inject + key must not reorder.
        InjectRuntime.async { [weak self] in
            let delivered = EventInjector.injectText(text, reason: successReason)
            if delivered.reason == "ax_denied" {
                // Permission dropped after the MainActor check. FIFO hop:
                // DispatchQueue.main.async from injectQueue, never main.sync.
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        // A later voice/type already staged a newer payload — don't clobber.
                        if !LastTextPayload.isCurrent(text, gen: gen) {
                            InjectTelemetry.note(
                                "type clipboard superseded",
                                ok: true,
                                reason: "ax_denied_clipboard_ok"
                            )
                            MagicLog.event("type \(text.count)B truncated=\(truncated) ok=true reason=ax_denied_clipboard_ok (superseded, payload kept)")
                            self?.sendVoiceAck(to: id, ok: true, reason: "ax_denied_clipboard_ok")
                            return
                        }
                        let fallback = EventInjector.clipboardFallbackKeepingPayload(text)
                        InjectTelemetry.note(
                            fallback.ok ? "type clipboard" : "type clipboard_fail",
                            ok: fallback.ok,
                            reason: fallback.reason
                        )
                        MagicLog.event("type \(text.count)B truncated=\(truncated) ok=\(fallback.ok) reason=\(fallback.reason)")
                        self?.sendVoiceAck(to: id, ok: fallback.ok, reason: fallback.reason)
                    }
                }
                return
            }
            MagicLog.event("type \(text.count)B truncated=\(truncated) ok=\(delivered.ok) reason=\(delivered.reason)")
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.sendVoiceAck(to: id, ok: delivered.ok, reason: delivered.reason)
                }
            }
        }
        lastEventSummary = "type \(text.count)\(truncated ? " trunc" : "") @ \(timestamp())"
    }

    /// 远程编辑 Mac 当前输入框
    /// JSON: { "type":"key", "action":"backspace|wordBackspace|wordLeft|…", "count":1 }
    /// Count/action normalized via pure `KeyProtocol` (clamped 1…200, allowlist).
    /// OPT-11/14: empty_action / bad_action / bad_count reject with no inject.
    private func handleKeyAction(_ json: [String: Any], from id: ObjectIdentifier) {
        let parsed = KeyProtocol.parseKey(from: json)
        if parsed.shouldReject {
            // empty_action | bad_action | bad_count — no inject
            InjectTelemetry.note("key \(parsed.reason)", ok: false, reason: parsed.reason)
            sendVoiceAck(to: id, ok: false, reason: parsed.reason)
            lastEventSummary = "key \(parsed.reason) @ \(timestamp())"
            return
        }
        let action = parsed.action
        let count = parsed.count
        guard parsed.allowed else {
            MagicLog.event("key action rejected (unknown): \(action)")
            InjectTelemetry.note("key unknown:\(action)", ok: false, reason: "unknown_action")
            sendVoiceAck(to: id, ok: false, reason: "unknown_action")
            lastEventSummary = "key reject \(action) @ \(timestamp())"
            return
        }
        let axFree = action == "launchpad" || action == "unstick" || action == "releaseModifiers"
            || action == "openAccessibility" || action == "showDesktop" || action == "desktop"
            || action == "missionControl" || action == "mission"
            || action == "notificationCenter"
        // AX off: ack on MainActor now (same serial as type clipboard). Hopping
        // injectQueue here let a later {type:type} ack overtake ⌫, and let
        // AX-free unstick overwrite lastKey *after* a later clipboard write
        // (lastKeyReason=unstick, lastKeyOk=true → health AX-off contract fail).
        // Do not clear LastTextPayload — key ax_denied is not a type/voice drop.
        if !EventInjector.hasAccessibilityPermission {
            if axFree {
                EventInjector.injectEditAction(action, count: count)
                sendVoiceAck(to: id, ok: true, reason: action)
                MagicLog.event("key action: \(action) x\(count) ax-free (payload kept)")
            } else {
                InjectTelemetry.note("key ax_denied", ok: false, reason: "ax_denied")
                MagicLog.event("key action: \(action) x\(count) ax_denied (payload kept)")
                sendVoiceAck(to: id, ok: false, reason: "ax_denied")
            }
            lastEventSummary = "key \(action)x\(count) @ \(timestamp())"
            return
        }
        // Same injectQueue as type unicode — never a second keySerial (⌫ overtake).
        // Ack hops back via main.async (FIFO with type acks), never Task { @MainActor }.
        InjectRuntime.async { [weak self] in
            let hadAx = EventInjector.hasAccessibilityPermission
            EventInjector.injectEditAction(action, count: count)
            let ok = hadAx || axFree
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.sendVoiceAck(to: id, ok: ok, reason: ok ? action : "ax_denied")
                }
            }
        }
        MagicLog.event("key action: \(action) x\(count)")
        lastEventSummary = "key \(action)x\(count) @ \(timestamp())"
    }

    private func handleVoiceText(_ json: [String: Any], from id: ObjectIdentifier) {
        guard let payload = json["text"] as? String, !payload.isEmpty else {
            MagicLog.event("voice: empty payload, skip")
            sendVoiceAck(to: id, ok: false, reason: "empty")
            return
        }
        let lang = json["lang"] as? String ?? "zh-CN"
        let autoPaste = json["autoPaste"] as? Bool ?? true
        let mode = (json["mode"] as? String ?? "append").lowercased()

        // Clipboard first (MainActor). ax=false still keeps text; do not clear last payload.
        LastTextPayload.remember(payload)
        let fallback = EventInjector.clipboardFallbackKeepingPayload(payload)
        guard fallback.ok else {
            MagicLog.event("voice: clipboard write failed (last payload kept)")
            InjectTelemetry.note("voice clipboard_fail", ok: false, reason: fallback.reason)
            sendVoiceAck(to: id, ok: false, reason: fallback.reason)
            return
        }
        let ax = EventInjector.hasAccessibilityPermission
        let ackReason = ax ? mode : "ax_denied_clipboard_ok"
        InjectTelemetry.note("voice clipboard", ok: true, reason: ackReason)
        MagicLog.event("voice: clipboard \(payload.count)B mode=\(mode) lang=\(lang) ax=\(ax) reason=\(ackReason) text=\(payload.prefix(80))")
        lastEventSummary = "voice \(mode) \(payload.count)B @ \(timestamp())"
        sendVoiceAck(to: id, ok: true, reason: ackReason)

        // AX off: paste cannot run. Do not hop injectQueue — replace-mode
        // selectAll noted ax_denied and clobbered lastKeyReason after a
        // successful clipboard write (same class as trailing unstick).
        // Type/key AX-off stay on MainActor; hopping here reordered vs them.
        if autoPaste && ax {
            InjectRuntime.async {
                // 粘贴前清粘滞键/鼠标，避免替换后 ⌫ 失灵
                EventInjector.releaseStuckButtons(reason: "before-voice-paste")
                EventInjector.releaseAllModifiers()
                if mode == "replace" {
                    EventInjector.injectEditAction("selectAll", count: 1)
                    usleep(12_000)
                    EventInjector.releaseAllModifiers()
                    usleep(4_000)
                }
                if EventInjector.hasAccessibilityPermission {
                    EventInjector.injectEditAction("paste", count: 1)
                    MagicLog.event("voice: simulated Cmd+V (chord)")
                } else {
                    MagicLog.event("voice: paste skipped — no Accessibility permission (payload kept)")
                }
                usleep(6_000)
                EventInjector.releaseAllModifiers()
            }
        } else if autoPaste {
            MagicLog.event("voice: paste skipped — no Accessibility permission (payload kept)")
        }
    }

    private func sendVoiceAck(to id: ObjectIdentifier, ok: Bool, reason: String?) {
        let payload: [String: Any] = [
            "type": "voice_ack",
            "ok": ok,
            "reason": reason ?? "",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let s = String(data: data, encoding: .utf8) {
            connections[id]?.sendText(s)
        }
    }

    /// Menu / log only. Inject + latency echo happen off MainActor (H12).
    private func noteBinaryUI(_ data: Data) {
        if data.count < 7 {
            MagicLog.event("binary \(data.count)B (too short, expect >= 7B)")
            lastEventSummary = "bin \(data.count)B @ \(timestamp())"
            onMessage?(.binary(data))
            return
        }
        let phase = data[0]
        if phase == 1 || phase == 20 {
            onMessage?(.binary(data))
            return
        }
        let dx = Int16(data[1]) | (Int16(data[2]) << 8)
        let dy = Int16(data[3]) | (Int16(data[4]) << 8)
        if phase >= 10 {
            var fingers: UInt8 = 1
            var gesture: UInt8 = 0
            if data.count >= 18 {
                fingers = data[13]
                gesture = data[14]
            }
            lastEventSummary = "gesture phase=\(phase) fingers=\(fingers) g=\(gesture) @ \(timestamp())"
        } else {
            let pressure = data[5]
            let buttons = data[6]
            var tMs: UInt32 = 0
            var seq: UInt16 = 0
            if data.count >= 11 {
                tMs = UInt32(data[7]) | (UInt32(data[8]) << 8) | (UInt32(data[9]) << 16) | (UInt32(data[10]) << 24)
            }
            if data.count >= 13 {
                seq = UInt16(data[11]) | (UInt16(data[12]) << 8)
            }
            MagicLog.event("binary \(data.count)B: phase=\(phase) dx=\(dx) dy=\(dy) p=\(pressure) btn=\(buttons) t=\(tMs) seq=\(seq)")
            lastEventSummary = "bin phase=\(phase) dx=\(dx) dy=\(dy) @ \(timestamp())"
        }
        onMessage?(.binary(data))
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    // MARK: - 广播(预留,B6 用)

    func broadcast(_ data: Data) {
        for conn in connections.values {
            conn.sendBinary(data)
        }
    }
}

// MARK: - 单个 WebSocket 连接

private final class WSConnection: @unchecked Sendable {
    let connection: NWConnection
    var onText: ((String) -> Void)?
    var onBinary: ((Data) -> Void)?
    var onClose: (() -> Void)?

    private var buffer = Data()
    private var handshakeDone = false
    private var closed = false
    private let lock = NSLock()
    /// POST body wait: /stt or /drop (file/photo/audio to pasteboard)
    private var pendingPost: (
        contentLength: Int,
        path: String,
        contentType: String,
        lang: String,
        filename: String,
        autoPaste: Bool
    )?

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveLoop()
            case .failed(let err):
                MagicLog.ws("conn failed: \(err)")
                self?.closeInternal()
            case .cancelled:
                self?.closeInternal()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInteractive))
    }

    private func receiveLoop() {
        guard !closed else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262144) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                MagicLog.ws("recv error: \(error)")
                self.closeInternal()
                return
            }
            if let data, !data.isEmpty {
                self.handleData(data)
            }
            if isComplete {
                self.closeInternal()
                return
            }
            self.receiveLoop()
        }
    }

    private func handleData(_ data: Data) {
        lock.lock()
        buffer.append(data)

        // P2-1b: finish collecting POST body
        if let pending = pendingPost {
            if buffer.count >= pending.contentLength {
                let body = Data(buffer.prefix(pending.contentLength))
                buffer.removeAll(keepingCapacity: false)
                pendingPost = nil
                lock.unlock()
                dispatchPostBody(
                    path: pending.path,
                    body: body,
                    contentType: pending.contentType,
                    lang: pending.lang,
                    filename: pending.filename,
                    autoPaste: pending.autoPaste
                )
            } else {
                lock.unlock()
            }
            return
        }
        lock.unlock()

        if !handshakeDone {
            // 找 HTTP 头结尾 \r\n\r\n
            let sep = Data([0x0D, 0x0A, 0x0D, 0x0A])
            guard let range = buffer.range(of: sep) else { return }
            let headerData = buffer.subdata(in: 0..<range.upperBound)
            buffer.removeSubrange(0..<range.upperBound)
            guard let header = String(data: headerData, encoding: .utf8) else {
                MagicLog.ws("invalid HTTP header encoding")
                closeInternal()
                return
            }

            // === 路由: WS upgrade 还是普通 HTTP ===
            let lower = header.lowercased()
            if lower.contains("upgrade: websocket") {
                if !handleHandshake(header) {
                    closeInternal()
                    return
                }
                handshakeDone = true
                MagicLog.ws("handshake done, buffer remaining=\(buffer.count)B")
            } else {
                let firstLine = header.components(separatedBy: "\r\n").first ?? "GET / HTTP/1.1"
                let parts = firstLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                let method = parts.first.map { String($0).uppercased() } ?? "GET"
                var rawPath = parts.count >= 2 ? String(parts[1]) : "/"
                if rawPath.hasPrefix("http://") || rawPath.hasPrefix("https://"),
                   let u = URL(string: rawPath) {
                    rawPath = u.path.isEmpty ? "/" : u.path
                    if let q = u.query, !q.isEmpty { rawPath += "?\(q)" }
                }
                MagicLog.ws("HTTP \(method) \(rawPath)")
                if method == "OPTIONS" {
                    serveCORSPreflight()
                    return
                }
                if method == "POST" {
                    beginHTTPPost(path: rawPath, header: header)
                    return
                }
                if method == "HEAD" {
                    serveStaticFile(path: rawPath, headOnly: true)
                } else {
                    serveStaticFile(path: rawPath, headOnly: false)
                }
                return
            }
        }

        // 解析 WebSocket 帧(可能多个)
        while let frame = parseFrame() {
            switch frame.opcode {
            case 0x1:  // text
                if let s = String(data: frame.payload, encoding: .utf8) {
                    onText?(s)
                }
            case 0x2:  // binary
                onBinary?(frame.payload)
            case 0x8:  // close
                MagicLog.ws("client sent close")
                sendCloseFrame()
                closeInternal()
                return
            case 0x9:  // ping
                sendPong(frame.payload)
            case 0xA:  // pong
                break
            default:
                MagicLog.ws("unknown opcode \(frame.opcode)")
            }
        }
    }

    private func beginHTTPPost(path: String, header: String) {
        var cleanPath = path.split(separator: "?").first.map(String.init) ?? path
        if cleanPath.isEmpty { cleanPath = "/" }
        if let decoded = cleanPath.removingPercentEncoding { cleanPath = decoded }

        let isStt = cleanPath == "/stt" || cleanPath == "/stt/"
        let isDrop = cleanPath == "/drop" || cleanPath == "/drop/" || cleanPath == "/upload" || cleanPath == "/upload/"
        guard isStt || isDrop else {
            serveJSON(
                status: "HTTP/1.1 404 Not Found",
                obj: ["ok": false, "reason": "not_found", "path": cleanPath]
            )
            return
        }

        let contentLength = Self.headerValue(header, name: "content-length").flatMap { Int($0) } ?? 0
        let contentType = Self.headerValue(header, name: "content-type") ?? "application/octet-stream"
        let lang = Self.headerValue(header, name: "x-magicpad-lang")
            ?? Self.queryValue(path, key: "lang")
            ?? "zh-CN"
        var filename = Self.headerValue(header, name: "x-magicpad-filename")
            ?? Self.queryValue(path, key: "name")
            ?? ""
        if let dec = filename.removingPercentEncoding { filename = dec }
        let autoPasteRaw = (Self.headerValue(header, name: "x-magicpad-autopaste")
            ?? Self.queryValue(path, key: "paste")
            ?? "1").lowercased()
        let autoPaste = !(autoPasteRaw == "0" || autoPasteRaw == "false" || autoPasteRaw == "no")

        let maxBytes = isDrop ? 50_000_000 : 10_000_000
        if contentLength < 0 {
            serveJSON(status: "HTTP/1.1 400 Bad Request", obj: [
                "ok": false, "reason": "missing_content_length", "text": "",
            ])
            return
        }
        if contentLength == 0 {
            serveJSON(status: "HTTP/1.1 400 Bad Request", obj: [
                "ok": false, "reason": "empty_body", "text": "",
            ])
            return
        }
        if contentLength > maxBytes {
            serveJSON(status: "HTTP/1.1 413 Payload Too Large", obj: [
                "ok": false, "reason": "too_large", "text": "",
            ])
            return
        }

        lock.lock()
        if buffer.count >= contentLength {
            let body = Data(buffer.prefix(contentLength))
            buffer.removeAll(keepingCapacity: false)
            lock.unlock()
            dispatchPostBody(
                path: cleanPath,
                body: body,
                contentType: contentType,
                lang: lang,
                filename: filename,
                autoPaste: autoPaste
            )
        } else {
            pendingPost = (contentLength, cleanPath, contentType, lang, filename, autoPaste)
            lock.unlock()
            MagicLog.ws("POST \(cleanPath) waiting body \(buffer.count)/\(contentLength)B")
        }
    }

    private func dispatchPostBody(
        path: String,
        body: Data,
        contentType: String,
        lang: String,
        filename: String,
        autoPaste: Bool
    ) {
        let p = path.lowercased()
        if p.hasPrefix("/drop") || p.hasPrefix("/upload") {
            serveDropUpload(body: body, contentType: contentType, filename: filename, autoPaste: autoPaste)
        } else {
            serveSTTUpload(body: body, contentType: contentType, lang: lang)
        }
    }

    private func serveDropUpload(body: Data, contentType: String, filename: String, autoPaste: Bool) {
        MagicLog.ws("POST /drop body=\(body.count)B type=\(contentType) name=\(filename) paste=\(autoPaste)")
        // FileDropPasteboard may hop to main for pasteboard
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let r = FileDropPasteboard.ingest(
                data: body,
                filename: filename.isEmpty ? nil : filename,
                contentType: contentType,
                autoPaste: autoPaste
            )
            var obj: [String: Any] = [
                "ok": r.ok,
                "bytes": r.bytes,
                "name": r.name,
                "path": r.path,
                "kind": r.kind,
                "pasted": r.pasted,
            ]
            if let reason = r.reason { obj["reason"] = reason }
            let status = r.ok ? "HTTP/1.1 200 OK" : "HTTP/1.1 422 Unprocessable Entity"
            DispatchQueue.main.async {
                self?.serveJSON(status: status, obj: obj)
            }
        }
    }

    private func serveSTTUpload(body: Data, contentType: String, lang: String) {
        MagicLog.ws("POST /stt body=\(body.count)B type=\(contentType) lang=\(lang)")
        Task { @MainActor in
            SpeechSession.shared.transcribeFile(
                data: body,
                lang: lang,
                contentType: contentType,
                preferOnDevice: true
            ) { [weak self] ok, text, reason, onDevice in
                guard let self else { return }
                var obj: [String: Any] = [
                    "ok": ok,
                    "text": text,
                    "onDevice": onDevice,
                    "engine": onDevice ? "whisper" : "apple",
                    "bytes": body.count,
                ]
                if let reason { obj["reason"] = reason }
                let status = ok ? "HTTP/1.1 200 OK" : "HTTP/1.1 422 Unprocessable Entity"
                self.serveJSON(status: status, obj: obj)
            }
        }
    }

    private func serveJSON(status: String, obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else {
            let fallback = Data("{\"ok\":false,\"reason\":\"encode\"}".utf8)
            sendHTTP(status: "HTTP/1.1 500 Internal Server Error", contentType: "application/json; charset=utf-8", body: fallback)
            return
        }
        sendHTTP(status: status, contentType: "application/json; charset=utf-8", body: data)
    }

    private func sendHTTP(status: String, contentType: String, body: Data) {
        let responseHead =
            "\(status)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n" +
            "X-MagicPad: 1\r\n" +
            Self.corsHeaders +
            "\r\n"
        let payload = Data(responseHead.utf8) + body
        connection.send(content: payload, completion: .contentProcessed { [weak self] err in
            if let err { MagicLog.ws("http send failed: \(err)") }
            self?.closeInternal()
        })
    }

    private static func headerValue(_ header: String, name: String) -> String? {
        let target = name.lowercased() + ":"
        for line in header.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix(target) {
                return line.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func queryValue(_ path: String, key: String) -> String? {
        guard let qIndex = path.firstIndex(of: "?") else { return nil }
        let query = path[path.index(after: qIndex)...]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2, String(kv[0]) == key {
                return String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }
        return nil
    }

    /// 每行以 CRLF 结束;整块末尾再带一个 CRLF,便于拼接
    private static let corsHeaders =
        "Access-Control-Allow-Origin: *\r\n" +
        "Access-Control-Allow-Methods: GET, HEAD, POST, OPTIONS\r\n" +
        "Access-Control-Allow-Headers: Content-Type, Upgrade, Connection, Sec-WebSocket-Key, Sec-WebSocket-Version, Sec-WebSocket-Extensions, X-MagicPad-Lang, X-MagicPad-Filename, X-MagicPad-AutoPaste\r\n" +
        "Cache-Control: no-store, no-cache, must-revalidate, max-age=0\r\n" +
        "Pragma: no-cache\r\n" +
        "Expires: 0\r\n"

    private func serveCORSPreflight() {
        let response =
            "HTTP/1.1 204 No Content\r\n" +
            Self.corsHeaders +
            "Connection: close\r\n" +
            "Content-Length: 0\r\n" +
            "\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] _ in
            self?.closeInternal()
        })
    }

    private func serveStaticFile(path: String, headOnly: Bool = false) {
        var cleanPath = path.split(separator: "?").first.map(String.init) ?? path
        if cleanPath.isEmpty { cleanPath = "/" }
        if cleanPath.count > 1 && cleanPath.hasSuffix("/") {
            cleanPath = String(cleanPath.dropLast())
        }
        if let decoded = cleanPath.removingPercentEncoding {
            cleanPath = decoded
        }

        let body: Data
        let contentType: String
        var statusLine = "HTTP/1.1 200 OK"

        if cleanPath == "/health" || cleanPath == "/healthz" || cleanPath == "/ping" || cleanPath == "/health.json" {
            body = Data(Self.healthJSON().utf8)
            contentType = "application/json; charset=utf-8"
        } else if cleanPath == "/" || cleanPath == "/index.html" || cleanPath == "/pad" || cleanPath == "/m" {
            if let (data, htmlPath) = StaticFileLocator.loadIndexHTML() {
                body = data
                MagicLog.ws("serve index \(data.count)B from \(StaticFileLocator.sourceLabel(htmlPath))")
            } else {
                let tried = StaticFileLocator.indexHTMLCandidates().joined(separator: " · ")
                body = Self.fallbackHTML(error: "index.html missing — tried: \(tried)")
                statusLine = "HTTP/1.1 503 Service Unavailable"
                MagicLog.ws("serve FALLBACK html; candidates=\(tried)")
            }
            contentType = "text/html; charset=utf-8"
        } else if cleanPath == "/favicon.ico"
                    || cleanPath == "/apple-touch-icon.png"
                    || cleanPath == "/apple-touch-icon-precomposed.png" {
            body = Data()
            contentType = "image/x-icon"
            statusLine = "HTTP/1.1 204 No Content"
        } else {
            statusLine = "HTTP/1.1 404 Not Found"
            body = Self.fallbackHTML(error: "404: \(cleanPath) — 请打开 / 或 /health")
            contentType = "text/html; charset=utf-8"
        }

        let responseHead =
            "\(statusLine)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n" +
            "X-MagicPad: 1\r\n" +
            Self.corsHeaders +
            "\r\n"
        let headData = Data(responseHead.utf8)
        let payload = headOnly ? headData : (headData + body)
        connection.send(content: payload, completion: .contentProcessed { [weak self] err in
            if let err {
                MagicLog.ws("static send failed: \(err)")
            }
            self?.closeInternal()
        })
    }

    /// /health JSON — 多设备排障(ip/ips/html 路径/ax);CORS + no-store 在响应头
    private static func healthJSON() -> String {
        let ip = LANDetector.ip
        let ips = LANDetector.allPrivateIPs
        let ipsJSON = "[" + ips.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        let ifaces = LANDetector.interfaceSummary
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let resolved = StaticFileLocator.resolvedIndexHTMLPath()
        let htmlOk = resolved != nil
        let htmlSource = resolved.map(StaticFileLocator.sourceLabel) ?? ""
        let ax = AXIsProcessTrusted()
        // stt: live WS Mac-mic + POST /stt file (SpeechSession is MainActor; detail via WS stt/status)
        let lastKey = InjectTelemetry.last
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let lastKeyReason = InjectTelemetry.lastReason
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let inj = InjectTelemetry.count
        let lastKeyOk = InjectTelemetry.lastOk
        let lastKeyAt = InjectTelemetry.lastAt
        let lastKeyCount = InjectTelemetry.lastCount
        let lastDropOk = DropTelemetry.lastOk
        // H778: 从未 drop 时 reason=never，避免 lastDropOk:false + 空 reason 被当成失败
        let lastDropReason = healthEscape(
            DropTelemetry.count == 0 && DropTelemetry.lastReason.isEmpty
                ? "never" : DropTelemetry.lastReason
        )
        let lastDropKind = DropTelemetry.lastKind
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let lastDropAt = DropTelemetry.lastAt
        let dropCount = DropTelemetry.count
        let env = InstallEnvironment.current
        let httpPort = env.httpPort
        let httpsPort = env.httpsPort
        let https = LANCert.isReady
        let httpsErr = LANCert.statusError
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let httpsURL = https ? env.httpsURL : ""
        let httpURL = env.httpURL
        let routeIface = healthEscape(env.routeIface)
        let lastGesture = healthEscape(GestureTelemetry.lastKind)
        let lastGestureReason = healthEscape(GestureTelemetry.lastReason)
        let lastGestureAt = GestureTelemetry.lastAt
        let lastGesturePhase = GestureTelemetry.lastPhase
        let gestureCount = GestureTelemetry.count
        let htmlRev = healthEscape(StaticFileLocator.htmlRev())
        let clients = WebSocketServer.liveClientCount
        let whisperReady = LocalWhisper.shared.isReady
        let whisperCached = LocalWhisper.shared.isCached
        let whisperModel = healthEscape(LocalWhisper.shared.modelLabel)
        // Privacy: no SSID, computer name, or /Users/… paths on the LAN.
        return "{\"ok\":true,\"service\":\"magicpad\",\"port\":\(httpPort),\"httpPort\":\(httpPort),\"httpsPort\":\(httpsPort),\"https\":\(https ? "true" : "false"),\"httpsUrl\":\"\(httpsURL)\",\"httpUrl\":\"\(httpURL)\",\"httpsError\":\"\(httpsErr)\",\"ip\":\"\(ip)\",\"ips\":\(ipsJSON),\"ifaces\":\"\(ifaces)\",\"routeIface\":\"\(routeIface)\",\"mdns\":\"\",\"html\":\(htmlOk),\"htmlPath\":\"\(htmlSource)\",\"htmlSource\":\"\(htmlSource)\",\"htmlRev\":\"\(htmlRev)\",\"binaryPath\":\"MagicPad.app\",\"injectQueue\":true,\"ax\":\(ax ? "true" : "false"),\"stt\":true,\"sttFile\":true,\"whisper\":true,\"whisperReady\":\(whisperReady ? "true" : "false"),\"whisperCached\":\(whisperCached ? "true" : "false"),\"whisperModel\":\"\(whisperModel)\",\"lastKey\":\"\(lastKey)\",\"lastKeyReason\":\"\(lastKeyReason)\",\"injectCount\":\(inj),\"lastKeyOk\":\(lastKeyOk ? "true" : "false"),\"lastKeyAt\":\(lastKeyAt),\"lastKeyCount\":\(lastKeyCount),\"lastDropOk\":\(lastDropOk ? "true" : "false"),\"lastDropReason\":\"\(lastDropReason)\",\"lastDropKind\":\"\(lastDropKind)\",\"lastDropAt\":\(lastDropAt),\"dropCount\":\(dropCount),\"lastGesture\":\"\(lastGesture)\",\"lastGestureReason\":\"\(lastGestureReason)\",\"lastGestureAt\":\(lastGestureAt),\"lastGesturePhase\":\(lastGesturePhase),\"gestureCount\":\(gestureCount),\"clients\":\(clients),\"ts\":\(Int(Date().timeIntervalSince1970))}"
    }

    private static func healthEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func fallbackHTML(error: String) -> Data {
        let ipHint = LANDetector.ip
        let html = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
        <meta name="theme-color" content="#0a0a14">
        <title>MagicPad</title></head>
        <body style="font-family:-apple-system,system-ui;padding:32px;background:#0a0a14;color:#f2f2f7;line-height:1.5;margin:0">
        <h1 style="font-size:28px;margin:0 0 12px">MagicPad</h1>
        <p style="color:#ff6b6b">\(error)</p>
        <p>请用手机浏览器打开(同一 Wi‑Fi,关闭 VPN):</p>
        <p style="font-family:ui-monospace;background:#1c1c24;padding:12px;border-radius:12px;word-break:break-all">http://\(ipHint):\(InstallEnvironment.current.httpPort)/</p>
        <p style="font-family:ui-monospace;background:#1c1c24;padding:12px;border-radius:12px;word-break:break-all;opacity:.9">HTTPS 录音: https://\(ipHint):\(InstallEnvironment.current.httpsPort)/</p>
        <p><a href="/" style="color:#6c8cff">打开操控页</a> · <a href="/health" style="color:#6c8cff">/health</a></p>
        </body></html>
        """
        return Data(html.utf8)
    }

    private func handleHandshake(_ header: String) -> Bool {
        let lines = header.components(separatedBy: "\r\n")
        var hasUpgrade = false
        var hasWebSocket = false
        var key: String?
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("upgrade:") {
                hasUpgrade = lower.contains("websocket")
            } else if lower.hasPrefix("connection:") {
                hasWebSocket = lower.contains("upgrade")
            } else if lower.hasPrefix("sec-websocket-key:") {
                key = line.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
            }
        }
        guard hasUpgrade, hasWebSocket, let key else {
            MagicLog.ws("handshake missing headers (upgrade=\(hasUpgrade) ws=\(hasWebSocket) key=\(key != nil))")
            return false
        }
        let accept = Self.computeAccept(key: key)
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(accept)\r
        \r

        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { [weak self] err in
            if let err {
                MagicLog.ws("send 101 failed: \(err)")
                self?.closeInternal()
            } else {
                MagicLog.ws("sent 101 Switching Protocols")
            }
        })
        return true
    }

    private static func computeAccept(key: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = key + magic
        let data = combined.data(using: .utf8) ?? Data()
        // SHA-1 (CryptoKit 需 macOS 10.15+)
        let hash = Self.sha1(data)
        return hash.base64EncodedString()
    }

    private static func sha1(_ data: Data) -> Data {
        // 简单 SHA-1,避免导入 CryptoKit 的额外开销
        var h: [UInt32] = [
            0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0,
        ]
        var msg = [UInt8](data)
        let origLen = msg.count
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0) }
        let bitLen = UInt64(origLen) * 8
        for i in (0..<8).reversed() {
            msg.append(UInt8((bitLen >> (i * 8)) & 0xFF))
        }
        for chunkStart in stride(from: 0, to: msg.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 {
                let off = chunkStart + i * 4
                w[i] = UInt32(msg[off]) << 24 | UInt32(msg[off+1]) << 16 | UInt32(msg[off+2]) << 8 | UInt32(msg[off+3])
            }
            for i in 16..<80 {
                let x = w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16]
                w[i] = (x << 1) | (x >> 31)
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4]
            for i in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch i {
                case 0..<20:
                    f = (b & c) | (~b & d)
                    k = 0x5A827999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }
                let temp = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ w[i]
                e = d; d = c; c = (b << 30) | (b >> 2); b = a; a = temp
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e
        }
        var out = Data()
        for v in h {
            out.append(UInt8((v >> 24) & 0xFF))
            out.append(UInt8((v >> 16) & 0xFF))
            out.append(UInt8((v >> 8) & 0xFF))
            out.append(UInt8(v & 0xFF))
        }
        return out
    }

    // MARK: - 帧解析

    private struct Frame {
        let fin: Bool
        let opcode: UInt8
        let payload: Data
    }

    private func parseFrame() -> Frame? {
        lock.lock()
        defer { lock.unlock() }
        guard buffer.count >= 2 else { return nil }
        let b0 = buffer[0]
        let b1 = buffer[1]
        let fin = (b0 & 0x80) != 0
        let opcode = b0 & 0x0F
        let masked = (b1 & 0x80) != 0
        var len = Int(b1 & 0x7F)
        var offset = 2
        switch len {
        case 126:
            guard buffer.count >= 4 else { return nil }
            len = Int(UInt16(buffer[2]) << 8 | UInt16(buffer[3]))
            offset = 4
        case 127:
            guard buffer.count >= 10 else { return nil }
            var v: UInt64 = 0
            for i in 0..<8 {
                v = (v << 8) | UInt64(buffer[2 + i])
            }
            guard v <= UInt64(Int.max) else { return nil }
            len = Int(v)
            offset = 10
        default:
            break
        }
        var maskKey: [UInt8] = []
        if masked {
            guard buffer.count >= offset + 4 else { return nil }
            maskKey = [buffer[offset], buffer[offset+1], buffer[offset+2], buffer[offset+3]]
            offset += 4
        }
        guard buffer.count >= offset + len else { return nil }
        var payload = buffer.subdata(in: offset..<(offset + len))
        if masked {
            for i in 0..<payload.count {
                payload[i] ^= maskKey[i % 4]
            }
        }
        buffer.removeSubrange(0..<(offset + len))
        return Frame(fin: fin, opcode: opcode, payload: payload)
    }

    // MARK: - 发送

    /// P2-4: 延迟 echo — 把 iOS 发来的 (seq, t_ms) 原样发回去,iOS 算 RTT
    /// 6 字节: [seq_lo, seq_hi, t_ms_0, t_ms_1, t_ms_2, t_ms_3]
    func sendLatencyEcho(seq: UInt16, tMs: UInt32) {
        var data = Data()
        data.append(UInt8(seq & 0xFF))
        data.append(UInt8((seq >> 8) & 0xFF))
        data.append(UInt8(tMs & 0xFF))
        data.append(UInt8((tMs >> 8) & 0xFF))
        data.append(UInt8((tMs >> 16) & 0xFF))
        data.append(UInt8((tMs >> 24) & 0xFF))
        sendBinary(data)
    }

    func sendBinary(_ data: Data) {
        guard handshakeDone, !closed else { return }
        var frame = Data()
        frame.append(0x82)  // FIN + binary opcode
        let len = data.count
        if len < 126 {
            frame.append(UInt8(len))
        } else if len < 65536 {
            frame.append(0x7E)
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        } else {
            frame.append(0x7F)
            for i in (0..<8).reversed() {
                frame.append(UInt8((UInt64(len) >> (i * 8)) & 0xFF))
            }
        }
        frame.append(data)
        connection.send(content: frame, completion: .contentProcessed { err in
            if let err {
                MagicLog.ws("send binary failed: \(err)")
            }
        })
    }

    func sendText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        var frame = Data()
        frame.append(0x81)  // FIN + text opcode
        let len = data.count
        if len < 126 {
            frame.append(UInt8(len))
        } else if len < 65536 {
            frame.append(0x7E)
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        } else {
            frame.append(0x7F)
            for i in (0..<8).reversed() {
                frame.append(UInt8((UInt64(len) >> (i * 8)) & 0xFF))
            }
        }
        frame.append(data)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func sendPong(_ payload: Data) {
        var frame = Data()
        frame.append(0x8A)  // FIN + pong
        let len = payload.count
        if len < 126 {
            frame.append(UInt8(len))
        } else {
            frame.append(0x7E)
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        }
        frame.append(payload)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func sendCloseFrame() {
        var frame = Data()
        frame.append(0x88)  // FIN + close
        frame.append(0x00)  // zero payload
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    // MARK: - 关闭

    func close() {
        closeInternal()
    }

    private func closeInternal() {
        lock.lock()
        let wasClosed = closed
        closed = true
        lock.unlock()
        guard !wasClosed else { return }
        connection.cancel()
        onClose?()
    }
}
