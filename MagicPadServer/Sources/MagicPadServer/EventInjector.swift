// EventInjector.swift
// Phase 1.6 - B6: CGEvent 注入
//
// 把 iOS 端的 binary 帧转成 macOS 系统级光标事件
//
// 权限要求:
//   - 辅助功能(Accessibility)
//   - 首次需要用户在系统设置 → 隐私与安全性 → 辅助功能 里勾选
//
// 限制(MVP):
//   - 多指手势:单击 / 双击 / 右键 / 滚轮 / 捏合 / 三·四指系统手势 / 查词 / 通知中心
//   - IOKit HID 留给 Phase 4(目前用 CGEventPost,够用)

import AppKit
import CoreGraphics
import ApplicationServices
import Darwin
import MagicPadCore

/// 键注入观测（非 MainActor，供 /health 读取；锁保护）
enum InjectTelemetry: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _last = "—"
    nonisolated(unsafe) private static var _count: UInt64 = 0
    nonisolated(unsafe) private static var _lastOk = false
    nonisolated(unsafe) private static var _lastAt: TimeInterval = 0
    /// Protocol reason: backspace | ax_denied | empty_type | unknown_action | empty_action | bad_count | …
    nonisolated(unsafe) private static var _lastReason = ""
    /// Last successful key inject count (OPT-14 /health lastKeyCount); 0 until first success.
    nonisolated(unsafe) private static var _lastCount: Int = 0
    static var last: String {
        lock.lock(); defer { lock.unlock() }
        return _last
    }
    static var count: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
    /// Last inject success flag (false for ax_denied / failed inject).
    static var lastOk: Bool {
        lock.lock(); defer { lock.unlock() }
        return _lastOk
    }
    /// Epoch seconds of last `note` (0 if never).
    static var lastAt: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return _lastAt
    }
    /// Last protocol reason string (empty if never noted with reason).
    static var lastReason: String {
        lock.lock(); defer { lock.unlock() }
        return _lastReason
    }
    /// Last success-path key count for /health `lastKeyCount`.
    static var lastCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _lastCount
    }
    /// - Parameters:
    ///   - s: human-readable lastKey label
    ///   - ok: inject / protocol success
    ///   - reason: protocol reason for /health `lastKeyReason` (canonical action or error code)
    ///   - count: on success, updates /health `lastKeyCount` when non-nil
    static func note(_ s: String, ok: Bool = true, reason: String = "", count: Int? = nil) {
        lock.lock()
        _last = s
        _count &+= 1
        _lastOk = ok
        _lastAt = Date().timeIntervalSince1970
        if !reason.isEmpty {
            _lastReason = reason
        } else if !ok {
            _lastReason = "ax_denied"
        } else {
            _lastReason = s
        }
        if ok, let c = count {
            _lastCount = c
        }
        lock.unlock()
    }
}

/// Last two-finger / gesture classify for /health (H2-3). No inject.
enum GestureTelemetry: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _kind = ""
    nonisolated(unsafe) private static var _reason = ""
    nonisolated(unsafe) private static var _at: TimeInterval = 0
    nonisolated(unsafe) private static var _phase: Int = 0
    nonisolated(unsafe) private static var _count: UInt64 = 0
    static var lastKind: String {
        lock.lock(); defer { lock.unlock() }
        return _kind
    }
    static var lastReason: String {
        lock.lock(); defer { lock.unlock() }
        return _reason
    }
    static var lastAt: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return _at
    }
    static var lastPhase: Int {
        lock.lock(); defer { lock.unlock() }
        return _phase
    }
    static var count: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
    static func note(kind: String, reason: String, phase: Int = 0) {
        let k = String(kind.prefix(32))
        let r = String(reason.prefix(64))
        lock.lock()
        _kind = k
        _reason = r
        _phase = phase
        _at = Date().timeIntervalSince1970
        _count &+= 1
        lock.unlock()
    }
    static func kindForPhase(_ phase: UInt8) -> String {
        switch phase {
        case 10: return "dbl"
        case 11: return "right"
        case 20: return "scroll"
        case 21: return "pinch"
        case 22: return "triple"
        case 23: return "smartzoom"
        case 24: return "mission"
        default: return "phase\(phase)"
        }
    }
}

/// Pointer / scroll / click / paste 共用的 userInteractive 串行队列。
/// 热路径不再 hop MainActor；键鼠同一队列，避免 leftButtonDown 竞态。
enum InjectRuntime {
    private static let specific = DispatchSpecificKey<UInt8>()
    static let queue: DispatchQueue = {
        let q = DispatchQueue(label: "app.magicpad.inject", qos: .userInteractive)
        q.setSpecific(key: specific, value: 1)
        return q
    }()

    static var isCurrent: Bool { DispatchQueue.getSpecific(key: specific) != nil }

    static func async(_ body: @escaping @Sendable () -> Void) {
        queue.async(execute: body)
    }

    static func sync(_ body: () -> Void) {
        if isCurrent {
            body()
            return
        }
        queue.sync(execute: body)
    }
}

/// Last type/voice string staged for clipboard or unicode inject.
/// Never cleared on ax_denied — dropping it is how text disappeared when AX was off.
/// `remember` is last-write-wins on MainActor. `keepIfEmpty` is for injectQueue
/// so a delayed `injectText` cannot clobber a newer voice/type payload.
enum LastTextPayload: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _text = ""
    nonisolated(unsafe) private static var _gen: UInt64 = 0

    /// Always overwrite. Used on MainActor for the current type/voice message.
    /// Empty is ignored — that would drop the last payload (ax_denied rule).
    @discardableResult
    static func remember(_ text: String) -> UInt64 {
        guard !text.isEmpty else { return 0 }
        lock.lock()
        _text = text
        _gen &+= 1
        let g = _gen
        lock.unlock()
        return g
    }

    /// injectQueue only: do not clobber a newer MainActor payload.
    static func keepIfEmpty(_ text: String) {
        guard !text.isEmpty else { return }
        lock.lock()
        if _text.isEmpty {
            _text = text
            _gen &+= 1
        }
        lock.unlock()
    }

    static var text: String {
        lock.lock(); defer { lock.unlock() }
        return _text
    }

    /// `gen == 0` → string compare only (no token from remember).
    static func isCurrent(_ text: String, gen: UInt64 = 0) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if gen != 0 { return _gen == gen && _text == text }
        return _text == text
    }
}

/// Ack payload for `{type,text}` / clipboard fallback. Not a new WS field set —
/// `ok` + `reason` already exist on voice_ack.
struct TextDeliverResult: Sendable {
    let ok: Bool
    let reason: String
}

enum EventInjector: @unchecked Sendable {
    /// Type/key share `InjectRuntime` (injectQueue). Do not add a second
    /// keySerial queue — that let ⌫ overtake type vs pointer/paste.
    /// Nested sync is re-entrant via isCurrent.
    private static func onKeySerial(_ body: () -> Void) {
        InjectRuntime.sync(body)
    }

    /// 鼠标按钮位掩码(与 MagicPad 协议 buttons 字段对应)
    enum Button: UInt8 {
        case left = 0x01
        case right = 0x02
        case middle = 0x04
    }

    /// 事件类型
    enum EventType: UInt8 {
        case down = 0
        case move = 1
        case up = 2
        case cancel = 3
    }

    /// 检测辅助功能权限（C API，任意线程可调）
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// 主动请求辅助功能权限(弹系统对话框,user 在对话框点"打开系统设置"或"拒绝/允许")
    /// kAXTrustedCheckOptionPrompt 是 Swift 6 拒绝访问的 var,直接用字面量字符串
    /// (kAXTrustedCheckOptionPrompt 的字面量值是 "AXTrustedCheckOptionPrompt",系统不会变)
    static func requestAccessibilityPermission() {
        if Thread.isMainThread {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        } else {
            DispatchQueue.main.async {
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                AXIsProcessTrustedWithOptions(options)
            }
        }
    }

    /// 打开系统设置到辅助功能页(让用户手动勾选)
    static func openAccessibilitySettings() {
        // macOS 13+ URL scheme
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]
        if Thread.isMainThread {
            for s in urls {
                if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
            }
        } else {
            DispatchQueue.main.async {
                for s in urls {
                    if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
                }
            }
        }
    }

    /// 服务端左键是否处于按下(防止 orphan drag 选中文字)。仅 InjectRuntime.queue 读写。
    nonisolated(unsafe) private static var leftButtonDown = false
    nonisolated(unsafe) private static var rightButtonDown = false
    /// H777: last binary frame — hello 不能无脑松键（bumpResumePing 拖选中每 400ms 会 hello）
    nonisolated(unsafe) private static var lastFrameAt: TimeInterval = 0

    /// WS 二进制帧注入（H12：在 InjectRuntime 上跑，不经 MainActor）
    static func consumeBinaryFrame(_ data: Data) {
        guard data.count >= 7 else { return }
        lastFrameAt = Date().timeIntervalSince1970
        let phase = data[0]
        let dx = Int16(data[1]) | (Int16(data[2]) << 8)
        let dy = Int16(data[3]) | (Int16(data[4]) << 8)
        let pressure = data[5]
        let buttons = data[6]
        var ext: Int16 = 0
        if data.count >= 18 {
            ext = Int16(data[15]) | (Int16(data[16]) << 8)
        }

        if phase >= 10 {
            GestureTelemetry.note(kind: GestureTelemetry.kindForPhase(phase), reason: "frame", phase: Int(phase))
            switch phase {
            case 10:
                MagicLog.event("gesture: dblClick")
                injectDoubleClick()
            case 11:
                MagicLog.event("gesture: rightClick")
                injectRightClick()
            case 20:
                if dx != 0 || dy != 0 {
                    injectScroll(dx: dx, dy: dy)
                }
            case 21:
                let scale = Double(ext) / 1000.0
                MagicLog.event("gesture: pinch scale=\(scale)")
                injectPinch(scale: scale)
            case 22:
                MagicLog.event("gesture: tripleClick")
                injectTripleClick()
            case 23:
                MagicLog.event("gesture: smartZoom")
                injectSmartZoom()
            case 24:
                let dir = UInt8(max(0, min(3, Int(ext))))
                MagicLog.event("gesture: missionControl dir=\(dir)")
                injectMissionControl(direction: dir)
            default:
                if let eventType = EventType(rawValue: phase) {
                    injectMouse(type: eventType, dx: dx, dy: dy, pressure: pressure, buttons: buttons)
                } else {
                    MagicLog.event("gesture: unknown phase=\(phase)")
                }
            }
            return
        }
        if let eventType = EventType(rawValue: phase) {
            injectMouse(type: eventType, dx: dx, dy: dy, pressure: pressure, buttons: buttons)
        }
    }

    /// 主入口:把协议帧转成系统事件
    /// - Parameters:
    ///   - type: down/move/up/cancel
    ///   - dx: 像素 delta X
    ///   - dy: 像素 delta Y
    ///   - pressure: 0-255(MVP 暂不用)
    ///   - buttons: 位掩码 0x01=左 0x02=右
    static func injectMouse(type: EventType, dx: Int16, dy: Int16, pressure: UInt8 = 0, buttons: UInt8 = 0) {
        // === P2-1: 加速度曲线(先 transform,纯计算,放权限检查之前) ===
        let (accelDx, accelDy) = applyAcceleration(dx: dx, dy: dy)

        guard hasAccessibilityPermission else {
            // 不每次都 log,降频
            Self.warnAboutPermission()
            return
        }

        // 当前光标位置
        let current = CGEvent(source: nil)?.location ?? .zero
        let newPos = CGPoint(
            x: max(0, min(current.x + CGFloat(accelDx), 100_000)),
            y: max(0, min(current.y + CGFloat(accelDy), 100_000))
        )

        let wantRight = (buttons & 0x02) != 0
        // down 时:显式右键 → 右;否则左(客户端 tap 带 buttons=1)
        let button: CGMouseButton = wantRight ? .right : .left

        switch type {
        case .down:
            if wantRight {
                rightButtonDown = true
            } else {
                leftButtonDown = true
            }
            let event = CGEvent(
                mouseEventSource: nil,
                mouseType: wantRight ? .rightMouseDown : .leftMouseDown,
                mouseCursorPosition: newPos,
                mouseButton: button
            )
            // 明确按下态,避免部分 app 忽略
            event?.setIntegerValueField(.mouseEventClickState, value: 1)
            event?.post(tap: .cghidEventTap)

        case .move:
            // 关键: 仅当「本会话已 down」且 buttons 有左键时才 drag。
            // 客户端若误带 buttons=1,也绝不在无 down 时 drag → 杜绝滑过选字。
            let canDragLeft = leftButtonDown && (buttons & 0x01) != 0
            let canDragRight = rightButtonDown && (buttons & 0x02) != 0
            if canDragLeft {
                let event = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .leftMouseDragged,
                    mouseCursorPosition: newPos,
                    mouseButton: .left
                )
                event?.post(tap: .cghidEventTap)
            } else if canDragRight {
                let event = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .rightMouseDragged,
                    mouseCursorPosition: newPos,
                    mouseButton: .right
                )
                event?.post(tap: .cghidEventTap)
            } else {
                // 纯移动:永远 mouseMoved(无按钮)
                let event = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .mouseMoved,
                    mouseCursorPosition: newPos,
                    mouseButton: .left
                )
                event?.post(tap: .cghidEventTap)
            }

        case .up:
            // 只在「本会话已 down」时发 up,避免 orphan leftMouseUp 点中文字/抢焦点
            if rightButtonDown || wantRight {
                rightButtonDown = false
                let event = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .rightMouseUp,
                    mouseCursorPosition: newPos,
                    mouseButton: .right
                )
                event?.post(tap: .cghidEventTap)
            }
            if leftButtonDown || (buttons & 0x01) != 0 {
                leftButtonDown = false
                let event = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .leftMouseUp,
                    mouseCursorPosition: newPos,
                    mouseButton: .left
                )
                event?.post(tap: .cghidEventTap)
            }

        case .cancel:
            // 强制松开,避免卡在 drag
            let pos = CGEvent(source: nil)?.location ?? newPos
            if leftButtonDown {
                leftButtonDown = false
                let event = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .leftMouseUp,
                    mouseCursorPosition: pos,
                    mouseButton: .left
                )
                event?.post(tap: .cghidEventTap)
            }
            if rightButtonDown {
                rightButtonDown = false
                let event = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .rightMouseUp,
                    mouseCursorPosition: pos,
                    mouseButton: .right
                )
                event?.post(tap: .cghidEventTap)
            }
            MagicLog.event("cancel: force button release")
        }
    }

    /// 客户端断开 / 崩溃时强制松键，避免 Mac 卡在 drag 选字
    static func releaseStuckButtons(reason: String = "disconnect") {
        let wasLeft = leftButtonDown
        let wasRight = rightButtonDown
        guard wasLeft || wasRight else { return }
        let pos = CGEvent(source: nil)?.location ?? .zero
        if wasLeft {
            leftButtonDown = false
            if hasAccessibilityPermission {
                let event = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .leftMouseUp,
                    mouseCursorPosition: pos,
                    mouseButton: .left
                )
                event?.post(tap: .cghidEventTap)
            }
        }
        if wasRight {
            rightButtonDown = false
            if hasAccessibilityPermission {
                let event = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .rightMouseUp,
                    mouseCursorPosition: pos,
                    mouseButton: .right
                )
                event?.post(tap: .cghidEventTap)
            }
        }
        MagicLog.event("releaseStuckButtons(\(reason)) L=\(wasLeft) R=\(wasRight)")
    }

    /// H777: 仅当板面空闲才松 stuck 键。手机休眠/NAT 无 close 时 hello 能清幽灵拖拽；拖选中的 hello 不松。
    static func releaseIdleStuckButtons(reason: String, idleSec: TimeInterval = 1.2) {
        guard leftButtonDown || rightButtonDown else { return }
        let idle = Date().timeIntervalSince1970 - lastFrameAt
        guard idle >= idleSec else { return }
        releaseStuckButtons(reason: "\(reason) idle=\(String(format: "%.1f", idle))s")
    }

    // MARK: - P3 多指手势

    /// 双击(快速 down+up 两次)
    static func injectDoubleClick() {
        guard hasAccessibilityPermission else {
            Self.warnAboutPermission()
            return
        }
        let pos = CGEvent(source: nil)?.location ?? .zero
        for _ in 0..<2 {
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pos, mouseButton: .left)
            down?.post(tap: .cghidEventTap)
            usleep(12_000)
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left)
            up?.post(tap: .cghidEventTap)
            usleep(16_000)
        }
        MagicLog.event("dblClick at \(pos)")
    }

    /// 右键 / 上下文菜单 (P0-3)
    ///
    /// pure rightMouse 在部分 app 不弹菜单; **Control + 左键** 是 macOS 传统
    /// secondary click,与系统触控板「点按或轻点」副键等价,最稳。
    /// 只走一条 path,避免双发导致菜单闪灭或点中第一项。
    static func injectRightClick() {
        guard hasAccessibilityPermission else {
            Self.warnAboutPermission()
            // 重建 .app / 改 codesign 后常掉授权 — 主动弹一次系统提示
            requestAccessibilityPermission()
            return
        }
        // 若左/右键卡在按下态,先松开,否则菜单会被吃掉
        let pos0 = CGEvent(source: nil)?.location ?? .zero
        if leftButtonDown {
            leftButtonDown = false
            let upL = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pos0, mouseButton: .left)
            upL?.post(tap: .cghidEventTap)
            usleep(20_000)
        }
        if rightButtonDown {
            rightButtonDown = false
            let upR = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: pos0, mouseButton: .right)
            upR?.post(tap: .cghidEventTap)
            usleep(15_000)
        }

        let pos = CGEvent(source: nil)?.location ?? .zero
        let src = CGEventSource(stateID: .hidSystemState)

        // Control 按下(带 maskControl) → 左键 down/up(flags=Control) → Control 松开
        if let ctrlDown = CGEvent(keyboardEventSource: src, virtualKey: 0x3B /* kVK_Control */, keyDown: true) {
            ctrlDown.flags = .maskControl
            ctrlDown.post(tap: .cghidEventTap)
        }
        usleep(18_000)
        if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: pos, mouseButton: .left) {
            down.flags = .maskControl
            down.setIntegerValueField(.mouseEventClickState, value: 1)
            down.post(tap: .cghidEventTap)
        }
        usleep(55_000)
        if let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left) {
            up.flags = .maskControl
            up.setIntegerValueField(.mouseEventClickState, value: 1)
            up.post(tap: .cghidEventTap)
        }
        usleep(18_000)
        if let ctrlUp = CGEvent(keyboardEventSource: src, virtualKey: 0x3B, keyDown: false) {
            ctrlUp.flags = []
            ctrlUp.post(tap: .cghidEventTap)
        }

        MagicLog.event("rightClick(ctrl+left) at \(pos)")
    }

    /// Write string to general pasteboard. Remembers last payload *before*
    /// `clearContents` so a failed pasteboard write cannot drop server-side text.
    /// Never restores a previous clip on failure — that dropped the new text
    /// after a file drop / newline mismatch. Stale hops (newer payload already
    /// staged) skip the write and still count as success so ax_denied cannot
    /// clobber a later voice/type.
    /// Never call from injectQueue (would `main.sync` → deadlock with drop paste).
    @discardableResult
    static func writeClipboardText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let staged = LastTextPayload.text
        if !staged.isEmpty && staged != text {
            MagicLog.event("writeClipboardText stale skip (payload kept)")
            return true
        }
        // Do not remember() when already current — that bumped gen and made
        // the AX-denied delayed isCurrent(gen:) check fail (looked like a drop).
        if staged.isEmpty {
            LastTextPayload.remember(text)
        }
        if InjectRuntime.isCurrent {
            MagicLog.event("writeClipboardText refused on injectQueue (payload kept)")
            return false
        }
        var copied = false
        let work = {
            let pb = NSPasteboard.general
            func attempt() -> Bool {
                let item = NSPasteboardItem()
                guard item.setString(text, forType: .string) else { return false }
                pb.clearContents()
                if pb.writeObjects([item]) { return true }
                pb.clearContents()
                return pb.setString(text, forType: .string)
            }
            copied = attempt()
            if !copied {
                copied = attempt()
            }
            if copied {
                // Diagnostics only. Strict == used to treat \n vs \r\n as failure
                // and then restore-previous dropped this text.
                let got = pb.string(forType: .string)
                if got != text {
                    MagicLog.event("writeClipboardText readback differs (kept write; payload kept)")
                }
            } else {
                MagicLog.event("writeClipboardText write failed (payload kept)")
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
        return copied
    }

    /// AX-off type/voice path: clipboard write + `ax_denied_clipboard_ok`.
    /// Must run off injectQueue (MainActor). Payload is remembered first.
    static func clipboardFallbackKeepingPayload(_ text: String) -> TextDeliverResult {
        guard !text.isEmpty else {
            return TextDeliverResult(ok: false, reason: "empty_type")
        }
        let copied = writeClipboardText(text)
        return TextDeliverResult(
            ok: copied,
            reason: copied ? "ax_denied_clipboard_ok" : "clipboard"
        )
    }

    /// 向 Mac 当前焦点插入任意文本（对话框 / 验证码 / 输入框）
    /// AX 开：CGEvent unicode，不经剪贴板。AX 关：remember payload 后返回 ax_denied，
    /// 由 WS 层在 MainActor 写剪贴板并 ack ax_denied_clipboard_ok（不丢字）。
    /// Must already be on injectQueue so ⌫ / type cannot reorder vs pointer/paste.
    /// - Parameter reason: protocol reason for telemetry (`type` | `type_truncated`) when injected
    @discardableResult
    static func injectText(_ text: String, reason: String = "type") -> TextDeliverResult {
        guard !text.isEmpty else {
            return TextDeliverResult(ok: false, reason: "empty_type")
        }
        // Caller already `remember`d on MainActor. keepIfEmpty only if unstaged —
        // remember() here used to clobber a later voice/type payload (ax_denied drop).
        LastTextPayload.keepIfEmpty(text)
        guard hasAccessibilityPermission else {
            Self.warnAboutPermission()
            // Payload kept. Caller writes clipboard on MainActor (never from
            // injectQueue). Reason becomes ax_denied_clipboard_ok there.
            return TextDeliverResult(ok: false, reason: "ax_denied")
        }
        onKeySerial {
            releaseStuckButtons(reason: "before-type")
            releaseAllModifiers()

            let src = CGEventSource(stateID: .combinedSessionState)
            var n = 0
            for ch in text {
                var utf16 = Array(String(ch).utf16)
                guard !utf16.isEmpty else { continue }
                if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
                    down.flags = []
                    down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                    down.post(tap: .cghidEventTap)
                }
                usleep(3_000)
                if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                    up.flags = []
                    up.post(tap: .cghidEventTap)
                }
                usleep(3_000)
                n += 1
                if n % 32 == 0 { releaseAllModifiers() }
            }
            InjectTelemetry.note("type \(n)ch", ok: true, reason: reason)
            MagicLog.event("type \(n) graphemes: \(text.prefix(40))")
        }
        return TextDeliverResult(ok: true, reason: reason)
    }

    /// 纯按键（无修饰）— 删除/方向键热路径；串行队列
    /// - Parameter reason: protocol reason (canonical action name) for /health lastKeyReason
    @discardableResult
    static func injectPlainKey(
        _ keyCode: CGKeyCode,
        count: Int = 1,
        gapUs: useconds_t = 6_000,
        reason: String = "key"
    ) -> Bool {
        guard hasAccessibilityPermission else {
            Self.warnAboutPermission()
            InjectTelemetry.note("key ax_denied", ok: false, reason: "ax_denied")
            // Do not clear LastTextPayload — key ax_denied is not a type/voice drop.
            return false
        }
        onKeySerial {
            let n = KeyProtocol.clampKeyCount(count)
            // H805: stuck Cmd/Opt made ⌫ look like “can't delete” the Mac focus
            // (browser Back, word-delete). Clear once per burst, not per key.
            if keyCode == 0x33 || keyCode == 0x75 {
                releaseAllModifiers()
            }
            let src = CGEventSource(stateID: .combinedSessionState)
            for i in 0..<n {
                guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
                      let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else {
                    continue
                }
                down.flags = CGEventFlags(rawValue: 0)
                up.flags = CGEventFlags(rawValue: 0)
                down.post(tap: .cghidEventTap)
                usleep(4_000)
                up.post(tap: .cghidEventTap)
                if i + 1 < n { usleep(gapUs) }
            }
            InjectTelemetry.note("key \(keyCode)x\(n)", ok: true, reason: reason, count: n)
        }
        return true
    }

    /// AX-free keys (unstick / launchpad / …) still run when AX is off.
    /// `/health lastKeyOk=true` is reserved for type/voice clipboard success
    /// (`ax_denied_clipboard_ok`). Do not claim lastKeyOk on these keys when
    /// ax=false — that left lastKeyReason=unstick after smoke-type and failed
    /// the AX-off clipboard contract. Never clears LastTextPayload.
    /// When ax=false, do not clobber a kept clipboard / ax_denied lastKey —
    /// smoke-type's trailing unstick was overwriting lastKeyReason after a
    /// successful type/voice write (payload stayed; /health looked like a drop).
    static func noteAXFreeKey(_ action: String, performed: Bool) {
        if hasAccessibilityPermission {
            InjectTelemetry.note(
                action,
                ok: performed,
                reason: performed ? action : "\(action)_fail",
                count: performed ? 1 : nil
            )
            return
        }
        let prev = InjectTelemetry.lastReason
        if prev == "ax_denied_clipboard_ok" || prev == "ax_denied" {
            return
        }
        InjectTelemetry.note(action, ok: false, reason: action)
    }

    /// 通用快捷键 / 编辑键
    /// - count: backspace/left/right 等可连发（封顶 200，支持长按连删）
    static func injectEditAction(_ action: String, count: Int = 1) {
        if action == "launchpad" {
            let ok = injectLaunchpad()
            noteAXFreeKey("launchpad", performed: ok)
            return
        }
        if action == "notificationCenter" {
            let ok = injectNotificationCenter()
            noteAXFreeKey("notificationCenter", performed: ok)
            return
        }
        if action == "lookUp" {
            injectLookUp()
            return
        }
        if action == "showDesktop" || action == "desktop" {
            let ok = injectShowDesktop()
            noteAXFreeKey("showDesktop", performed: ok)
            return
        }
        if action == "missionControl" || action == "mission" {
            injectMissionControl(direction: 0)
            noteAXFreeKey("missionControl", performed: true)
            return
        }
        if action == "openAccessibility" {
            openAccessibilitySettings()
            noteAXFreeKey("openAccessibility", performed: true)
            MagicLog.event("edit: openAccessibility")
            return
        }
        if action == "releaseModifiers" || action == "unstick" {
            releaseAllModifiers()
            releaseStuckButtons(reason: "manual-unstick")
            noteAXFreeKey("unstick", performed: true)
            MagicLog.event("edit: unstick")
            return
        }
        guard hasAccessibilityPermission else {
            Self.warnAboutPermission()
            // Do not clear LastTextPayload on ax_denied.
            // Voice replace used to enqueue selectAll after a successful
            // clipboard write; noting ax_denied here clobbered lastKeyReason
            // (payload stayed; /health looked like a drop).
            if InjectTelemetry.lastReason != "ax_denied_clipboard_ok" {
                InjectTelemetry.note("edit ax_denied:\(action)", ok: false, reason: "ax_denied")
            }
            return
        }

        let n = KeyProtocol.clampKeyCount(count)

        // 热路径：⌫ / 方向 / 回车 — 不每次 release 修饰键
        switch action {
        case "backspace":
            injectPlainKey(0x33, count: n, gapUs: 5_000, reason: "backspace")
            MagicLog.event("edit: backspace x\(n)")
            return
        case "delete", "forwardDelete":
            injectPlainKey(0x75, count: n, gapUs: 5_000, reason: action == "delete" ? "delete" : "forwardDelete")
            MagicLog.event("edit: delete x\(n)")
            return
        case "left":
            injectPlainKey(0x7B, count: n, gapUs: 4_000, reason: "left")
            return
        case "right":
            injectPlainKey(0x7C, count: n, gapUs: 4_000, reason: "right")
            return
        case "up":
            injectPlainKey(0x7E, count: n, gapUs: 4_000, reason: "up")
            return
        case "down":
            injectPlainKey(0x7D, count: n, gapUs: 4_000, reason: "down")
            return
        case "enter", "return":
            injectPlainKey(0x24, count: 1, reason: "enter")
            return
        case "escape":
            injectPlainKey(0x35, count: 1, reason: "escape")
            return
        case "tab":
            // kVK_Tab = 0x30 — plain, no sticky modifiers
            injectPlainKey(0x30, count: n, gapUs: 4_000, reason: "tab")
            return
        case "home":
            // kVK_Home = 0x73
            injectPlainKey(0x73, count: n, gapUs: 4_000, reason: "home")
            return
        case "end":
            // kVK_End = 0x77
            injectPlainKey(0x77, count: n, gapUs: 4_000, reason: "end")
            return
        case "pageUp":
            // kVK_PageUp = 0x74 — plain, no sticky modifiers
            injectPlainKey(0x74, count: n, gapUs: 4_000, reason: "pageUp")
            return
        case "pageDown":
            // kVK_PageDown = 0x79
            injectPlainKey(0x79, count: n, gapUs: 4_000, reason: "pageDown")
            return
        default:
            break
        }

        // 带修饰键：整段串行（injectQueue，与 type/⌫ 同一条）
        onKeySerial {
            releaseStuckButtons(reason: "before-key:\(action)")
            releaseAllModifiers()

            switch action {
            case "selectAll":
                postKeyChord(keyCode: 0x00 /* A */, modifiers: .maskCommand)
            case "cut":
                postKeyChord(keyCode: 0x07 /* X */, modifiers: .maskCommand)
            case "copy":
                postKeyChord(keyCode: 0x08 /* C */, modifiers: .maskCommand)
            case "paste":
                postKeyChord(keyCode: 0x09 /* V */, modifiers: .maskCommand)
            case "undo":
                postKeyChord(keyCode: 0x06 /* Z */, modifiers: .maskCommand)
            case "wordBackspace":
                for i in 0..<n {
                    postKeyChord(keyCode: 0x33, modifiers: .maskAlternate)
                    if i + 1 < n { usleep(10_000) }
                }
            case "wordForwardDelete":
                // Option+FwdDel (kVK_ForwardDelete 0x75) — delete next word
                for i in 0..<n {
                    postKeyChord(keyCode: 0x75, modifiers: .maskAlternate)
                    if i + 1 < n { usleep(10_000) }
                }
            case "wordLeft":
                // Option+Left (kVK_LeftArrow 0x7B) — word boundary nav
                for i in 0..<n {
                    postKeyChord(keyCode: 0x7B, modifiers: .maskAlternate)
                    if i + 1 < n { usleep(10_000) }
                }
            case "wordRight":
                // Option+Right (kVK_RightArrow 0x7C)
                for i in 0..<n {
                    postKeyChord(keyCode: 0x7C, modifiers: .maskAlternate)
                    if i + 1 < n { usleep(10_000) }
                }
            case "selectLeft":
                // Shift+Left (kVK_LeftArrow 0x7B) — extend selection left
                for i in 0..<n {
                    postKeyChord(keyCode: 0x7B, modifiers: .maskShift)
                    if i + 1 < n { usleep(10_000) }
                }
            case "selectRight":
                // Shift+Right (kVK_RightArrow 0x7C) — extend selection right
                for i in 0..<n {
                    postKeyChord(keyCode: 0x7C, modifiers: .maskShift)
                    if i + 1 < n { usleep(10_000) }
                }
            case "selectWordLeft":
                // Shift+Option+Left — word-boundary selection left
                for i in 0..<n {
                    postKeyChord(keyCode: 0x7B, modifiers: [.maskShift, .maskAlternate])
                    if i + 1 < n { usleep(10_000) }
                }
            case "selectWordRight":
                // Shift+Option+Right — word-boundary selection right
                for i in 0..<n {
                    postKeyChord(keyCode: 0x7C, modifiers: [.maskShift, .maskAlternate])
                    if i + 1 < n { usleep(10_000) }
                }
            case "selectUp":
                // Shift+Up (kVK_UpArrow 0x7E) — extend selection up
                for i in 0..<n {
                    postKeyChord(keyCode: 0x7E, modifiers: .maskShift)
                    if i + 1 < n { usleep(10_000) }
                }
            case "selectDown":
                // Shift+Down (kVK_DownArrow 0x7D) — extend selection down
                for i in 0..<n {
                    postKeyChord(keyCode: 0x7D, modifiers: .maskShift)
                    if i + 1 < n { usleep(10_000) }
                }
            case "selectHome":
                // Shift+Home (kVK_Home 0x73) — select to line/doc start
                for i in 0..<n {
                    postKeyChord(keyCode: 0x73, modifiers: .maskShift)
                    if i + 1 < n { usleep(10_000) }
                }
            case "selectEnd":
                // Shift+End (kVK_End 0x77) — select to line/doc end
                for i in 0..<n {
                    postKeyChord(keyCode: 0x77, modifiers: .maskShift)
                    if i + 1 < n { usleep(10_000) }
                }
            case "selectPageUp":
                // Shift+PageUp (kVK_PageUp 0x74) — extend selection page up
                for i in 0..<n {
                    postKeyChord(keyCode: 0x74, modifiers: .maskShift)
                    if i + 1 < n { usleep(10_000) }
                }
            case "selectPageDown":
                // Shift+PageDown (kVK_PageDown 0x79) — extend selection page down
                for i in 0..<n {
                    postKeyChord(keyCode: 0x79, modifiers: .maskShift)
                    if i + 1 < n { usleep(10_000) }
                }
            case "redo":
                // Cmd+Shift+Z (kVK_ANSI_Z 0x06) — redo (pairs with undo Cmd+Z)
                for i in 0..<n {
                    postKeyChord(keyCode: 0x06, modifiers: [.maskCommand, .maskShift])
                    if i + 1 < n { usleep(10_000) }
                }
            case "lineStart":
                // Cmd+Left (kVK_LeftArrow 0x7B) — move to beginning of line
                for i in 0..<n {
                    postKeyChord(keyCode: 0x7B, modifiers: .maskCommand)
                    if i + 1 < n { usleep(10_000) }
                }
            case "lineEnd":
                // Cmd+Right (kVK_RightArrow 0x7C) — move to end of line
                for i in 0..<n {
                    postKeyChord(keyCode: 0x7C, modifiers: .maskCommand)
                    if i + 1 < n { usleep(10_000) }
                }
            case "selectLineStart":
                // Cmd+Shift+Left — select to beginning of line
                for i in 0..<n {
                    postKeyChord(keyCode: 0x7B, modifiers: [.maskCommand, .maskShift])
                    if i + 1 < n { usleep(10_000) }
                }
            case "selectLineEnd":
                // Cmd+Shift+Right — select to end of line
                for i in 0..<n {
                    postKeyChord(keyCode: 0x7C, modifiers: [.maskCommand, .maskShift])
                    if i + 1 < n { usleep(10_000) }
                }
            case "lineBackspace":
                // Cmd+⌫ (kVK_Delete 0x33) — delete to beginning of line
                for i in 0..<n {
                    postKeyChord(keyCode: 0x33, modifiers: .maskCommand)
                    if i + 1 < n { usleep(10_000) }
                }
            case "lineForwardDelete":
                // Cmd+FwdDel (kVK_ForwardDelete 0x75) — delete to end of line
                for i in 0..<n {
                    postKeyChord(keyCode: 0x75, modifiers: .maskCommand)
                    if i + 1 < n { usleep(10_000) }
                }
            case "clearField":
                postKeyChord(keyCode: 0x00, modifiers: .maskCommand)
                usleep(30_000)
                releaseAllModifiers()
                usleep(10_000)
                // plain key inside serial — call unlocked body once
                let src = CGEventSource(stateID: .combinedSessionState)
                for code: CGKeyCode in [0x33, 0x75] {
                    if let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true),
                       let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) {
                        down.flags = []; up.flags = []
                        down.post(tap: .cghidEventTap)
                        usleep(4_000)
                        up.post(tap: .cghidEventTap)
                        usleep(6_000)
                    }
                }
            default:
                MagicLog.event("unknown edit action: \(action)")
                return
            }
            releaseAllModifiers()
            InjectTelemetry.note("edit \(action)x\(n)", ok: true, reason: action, count: n)
            MagicLog.event("edit: \(action) x\(n)")
        }
    }

    /// 查词 / 数据检测：系统默认 Ctrl+Cmd+D（三指轻点 Look Up）
    static func injectLookUp() {
        guard hasAccessibilityPermission else {
            Self.warnAboutPermission()
            return
        }
        postKeyCombo(keyCode: 0x02 /* kVK_ANSI_D */, modifiers: [.maskControl, .maskCommand])
        MagicLog.event("lookUp: Ctrl+Cmd+D")
    }

    /// 通知中心：对齐触摸板「从右缘双指左滑」。
    @discardableResult
    static func injectNotificationCenter() -> Bool {
        if hasAccessibilityPermission {
            if clickControlCenterClock() {
                MagicLog.event("notificationCenter via ControlCenter AX")
                return true
            }
        } else if sendDockNotification("com.apple.dock.notificationcenter") {
            MagicLog.event("notificationCenter via Dock notify")
            return true
        }
        guard hasAccessibilityPermission else {
            Self.warnAboutPermission()
            return false
        }
        let saved = CGEvent(source: nil)?.location ?? .zero
        let pos = menuBarClockPoint()
        if let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pos, mouseButton: .left) {
            down.post(tap: .cghidEventTap)
        }
        usleep(12_000)
        if let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left) {
            up.post(tap: .cghidEventTap)
        }
        usleep(8_000)
        CGWarpMouseCursorPosition(saved)
        if let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: saved, mouseButton: .left) {
            move.post(tap: .cghidEventTap)
        }
        MagicLog.event("notificationCenter via clock click")
        return true
    }

    private static func menuBarClockPoint() -> CGPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var x = frame.maxX - 28
        var y = frame.maxY - 12
        if #available(macOS 12.0, *), let screen, screen.safeAreaInsets.top > 0 {
            x = frame.midX
            y = frame.maxY - 8
        }
        return CGPoint(x: x, y: y)
    }

    @discardableResult
    private static func clickControlCenterClock() -> Bool {
        let script = """
        tell application "System Events"
          if not (exists process "ControlCenter") then return false
          tell process "ControlCenter"
            set barItems to menu bar items of menu bar 1
            if (count of barItems) is 0 then return false
            repeat with itm in barItems
              set d to ""
              try
                set d to description of itm as text
              end try
              if d contains "Clock" or d contains "时钟" or d contains "Date" or d contains "日期" or d contains "Time" then
                click itm
                return true
              end if
            end repeat
            click (last item of barItems)
            return true
          end tell
        end tell
        """
        var err: NSDictionary?
        guard let apple = NSAppleScript(source: script) else { return false }
        apple.executeAndReturnError(&err)
        if let err {
            MagicLog.event("notificationCenter AX fail \(err)")
            return false
        }
        return true
    }

    /// 启动台。macOS 26 已删 Launchpad.app，改为 Apps 视图 / Dock 通知。
    @discardableResult
    static func injectLaunchpad() -> Bool {
        // 先打开真实 App：Tahoe 是 Apps.app；旧系统是 Launchpad.app。
        // Dock 通知 dlsym 成功不等于界面出现（H23 同类假成功）。
        let candidates = [
            "/System/Applications/Apps.app",
            "/System/Applications/Launchpad.app",
            "/Applications/Launchpad.app",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                let name = URL(fileURLWithPath: path).lastPathComponent
                let ok = NSWorkspace.shared.open(URL(fileURLWithPath: path))
                MagicLog.event("launchpad open \(name) ok=\(ok)")
                if ok { return true }
            }
        }
        if sendDockNotification("com.apple.launchpad.toggle") {
            MagicLog.event("launchpad via Dock toggle")
            return true
        }
        if sendDockNotification("com.apple.dock.launchpad") {
            MagicLog.event("launchpad via Dock launchpad")
            return true
        }
        guard hasAccessibilityPermission else {
            Self.warnAboutPermission()
            return false
        }
        // Tahoe Apps：Spotlight 后 ⌘1
        postKeyCombo(keyCode: 0x31, modifiers: .maskCommand)
        usleep(90_000)
        postKeyCombo(keyCode: 0x12, modifiers: .maskCommand)
        MagicLog.event("launchpad via Spotlight Cmd+1")
        return true
    }

    /// 显示桌面。macOS 26 上直接 exec Mission Control 二进制会被 SIGKILL，
    /// 改走 Dock 通知（与系统 stub 相同）+ LaunchServices。
    @discardableResult
    static func injectShowDesktop() -> Bool {
        if openMissionControlUI(mode: 1) {
            MagicLog.event("showDesktop via Dock notify")
            return true
        }
        guard hasAccessibilityPermission else {
            Self.warnAboutPermission()
            return false
        }
        // kVK_F11 = 0x67 — 先标准 F11
        postKeyCombo(keyCode: 0x67, modifiers: [])
        usleep(40_000)
        // 许多 Mac 键盘把 F 键当亮度/音量：带 secondaryFn 再发一次
        if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0x67, keyDown: true) {
            down.flags = .maskSecondaryFn
            down.post(tap: .cghidEventTap)
        }
        usleep(20_000)
        if let up = CGEvent(keyboardEventSource: nil, virtualKey: 0x67, keyDown: false) {
            up.flags = .maskSecondaryFn
            up.post(tap: .cghidEventTap)
        }
        usleep(40_000)
        // 旧快捷：Cmd+F3（Exposé 桌面，部分系统仍有效）
        postKeyCombo(keyCode: 0x63 /* kVK_F3 */, modifiers: .maskCommand)
        MagicLog.event("showDesktop F11+fnF11+CmdF3")
        return true
    }

    /// 三连击(选段 / 选行 / 选全文,具体看 app)
    /// 发送 3 个 down+up 周期,间隔 12ms down-up + 16ms 周期间
    static func injectTripleClick() {
        guard hasAccessibilityPermission else {
            Self.warnAboutPermission()
            return
        }
        let pos = CGEvent(source: nil)?.location ?? .zero
        for _ in 0..<3 {
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pos, mouseButton: .left)
            down?.post(tap: .cghidEventTap)
            usleep(12_000)
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left)
            up?.post(tap: .cghidEventTap)
            usleep(16_000)
        }
        MagicLog.event("tripleClick at \(pos)")
    }

    /// 智能缩放:Cmd+0(实际大小) / Cmd+9(适合窗口)
    /// Mac 的 "Smart Zoom" 手势实际是 toggle 行为(放大/还原)
    ///   Safari: 智能缩放 = 切换到 100% / 适应窗口
    ///   Preview / Photos: 智能缩放 = 适应窗口
    /// 我们发 Cmd+0 触发"实际大小"toggle(Safari / Chrome 等都会响应)
    static func injectSmartZoom() {
        guard hasAccessibilityPermission else {
            Self.warnAboutPermission()
            return
        }
        // Cmd + 0 (key code 0x1D = kVK_ANSI_0)
        postKeyCombo(keyCode: 0x1D, modifiers: .maskCommand)
        MagicLog.event("smartZoom: Cmd+0")
    }

    /// Mission Control 系列:三指 swipe 触发
    ///   up    = 打开 Mission Control.app（不依赖 Ctrl+↑ 是否勾选，也不强依赖 AX）
    ///   down  = Mission Control 二进制参数 2（当前 App 窗口）
    ///   left/right = 切桌面：热键勾着走 Ctrl+Arrow；没勾则调度中心+方向+回车
    /// - direction: 0=up, 1=down, 2=left, 3=right
    static func injectMissionControl(direction: UInt8) {
        switch direction {
        case 0:
            if openMissionControlUI(mode: 0) {
                MagicLog.event("missionControl: up via Mission Control.app")
                return
            }
        case 1:
            if openMissionControlUI(mode: 2) {
                MagicLog.event("missionControl: down via Mission Control 2")
                return
            }
        case 2:
            injectSpaceSwitch(goRight: false)
            return
        case 3:
            injectSpaceSwitch(goRight: true)
            return
        default:
            break
        }

        guard hasAccessibilityPermission else {
            Self.warnAboutPermission()
            return
        }
        let keyCode: CGKeyCode
        let label: String
        switch direction {
        case 0:  keyCode = 0x7E  /* kVK_UpArrow */;    label = "up (Mission Control)"
        case 1:  keyCode = 0x7D  /* kVK_DownArrow */;  label = "down (App Exposé)"
        default: keyCode = 0x7E; label = "up"
        }
        postKeyCombo(keyCode: keyCode, modifiers: .maskControl)
        MagicLog.event("missionControl: \(label) via Ctrl+Arrow fallback")
    }

    /// 切桌面：快捷键勾着走 Ctrl+Arrow；没勾则打开调度中心用方向键选空间（不依赖「左右移动空间」热键）。
    private static func injectSpaceSwitch(goRight: Bool) {
        let hotkeysOn = spaceSwitchHotkeysEnabled()
        if hasAccessibilityPermission, hotkeysOn != false {
            postSpaceHotkey(goRight: goRight)
            MagicLog.event("spaceSwitch \(goRight ? "right" : "left") via Ctrl+Arrow hotkeys=\(String(describing: hotkeysOn))")
            return
        }
        let opened = openMissionControlUI(mode: 0)
        if hasAccessibilityPermission {
            usleep(opened ? 280_000 : 50_000)
            postKeyCombo(keyCode: goRight ? 0x7C : 0x7B, modifiers: [])
            usleep(70_000)
            postKeyCombo(keyCode: 0x24, modifiers: [])
            MagicLog.event("spaceSwitch \(goRight ? "right" : "left") via MC+arrow")
            return
        }
        if opened {
            MagicLog.event("spaceSwitch opened MC (ax denied)")
        } else {
            Self.warnAboutPermission()
        }
    }

    /// 79=左一桌面, 81=右一桌面。读不到则当未知（nil）。
    private static func spaceSwitchHotkeysEnabled() -> Bool? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.symbolichotkeys.plist")
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        let keys = (dict["AppleSymbolicHotKeys"] as? [String: Any]) ?? dict
        func enabled(_ id: String) -> Bool? {
            guard let d = keys[id] as? [String: Any] else { return nil }
            if let e = d["enabled"] as? Bool { return e }
            if let e = d["enabled"] as? NSNumber { return e.boolValue }
            return nil
        }
        let left = enabled("79")
        let right = enabled("81")
        if left == nil && right == nil { return nil }
        return (left ?? false) || (right ?? false)
    }

    private static func postSpaceHotkey(goRight: Bool) {
        let src = CGEventSource(stateID: .hidSystemState)
        let ctrl: CGKeyCode = 0x3B
        let arrow: CGKeyCode = goRight ? 0x7C : 0x7B
        func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { return }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
        post(ctrl, down: true, flags: .maskControl)
        usleep(16_000)
        post(arrow, down: true, flags: .maskControl)
        usleep(14_000)
        post(arrow, down: false, flags: .maskControl)
        usleep(6_000)
        post(ctrl, down: false, flags: [])
        usleep(4_000)
        releaseAllModifiers()
    }

    /// mode 0 = 调度中心, 1 = 显示桌面, 2 = 当前 App 窗口。
    /// 不直接 exec 二进制：macOS 26 会 SIGKILL（exit 137），按钮看起来没反应。
    @discardableResult
    private static func openMissionControlUI(mode: Int) -> Bool {
        let note: String
        switch mode {
        case 1: note = "com.apple.showdesktop.awake"
        case 2: note = "com.apple.expose.front.awake"
        default: note = "com.apple.expose.awake"
        }
        if sendDockNotification(note) {
            return true
        }
        let appPath = "/System/Applications/Mission Control.app"
        guard FileManager.default.fileExists(atPath: appPath) else { return false }
        let url = URL(fileURLWithPath: appPath)
        if mode == 0 {
            return NSWorkspace.shared.open(url)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-n", "-a", appPath, "--args", "\(mode)"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            return true
        } catch {
            MagicLog.event("missionControl open mode=\(mode) fail \(error.localizedDescription)")
            return false
        }
    }

    /// 与 Mission Control.app stub 相同：CoreDockSendNotification。运行时 dlsym，不链私有头。
    @discardableResult
    private static func sendDockNotification(_ name: String) -> Bool {
        typealias Fn = @convention(c) (CFString, Int) -> Void
        let path = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        guard let handle = dlopen(path, RTLD_NOW) else { return false }
        guard let sym = dlsym(handle, "CoreDockSendNotification") else { return false }
        let fn = unsafeBitCast(sym, to: Fn.self)
        fn(name as CFString, 0)
        return true
    }

    /// 滚轮：按像素注入。旧实现 dx/10 取整，小于 10px 的滑动会被丢掉，双指像“死了一截”。
    static func injectScroll(dx: Int16, dy: Int16) {
        guard hasAccessibilityPermission else {
            Self.warnAboutPermission()
            return
        }
        guard dx != 0 || dy != 0 else { return }
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(dy),
            wheel2: Int32(dx),
            wheel3: 0
        )
        event?.post(tap: .cghidEventTap)
    }

    /// 捏合缩放(scale: 1.0=不变,1.5=放大 1.5x,0.5=缩小)
    ///
    /// 方案选择:
    ///   - CGEvent `.magnify` 是私有 API,Swift 6 不能用 (eventType: 不可初始化)
    ///   - 用键盘事件 Cmd+= / Cmd+-:Mac 所有 app 通用(Safari/Preview/Photos/Mail 都响应)
    ///   - iOS 端保证**每个捏合手势只发一次**(手势结束时),所以这里就直接 fire
    ///
    /// 键盘码(US ANSI):
    ///   = = 0x18 (kVK_ANSI_Equal)
    ///   - = 0x1B (kVK_ANSI_Minus)
    static func injectPinch(scale: Double) {
        guard hasAccessibilityPermission else {
            Self.warnAboutPermission()
            return
        }
        guard scale > 0 else { return }

        // 限幅,避免异常值
        let s = max(0.1, min(10.0, scale))

        if s > 1.0 {
            // 放大: Cmd+=  (US layout '=' key code 0x18)
            postKeyCombo(keyCode: 0x18, modifiers: .maskCommand)
            MagicLog.event("pinch zoom in (scale=\(s))")
        } else {
            // 缩小: Cmd+-  (US layout '-' key code 0x1B)
            postKeyCombo(keyCode: 0x1B, modifiers: .maskCommand)
            MagicLog.event("pinch zoom out (scale=\(s))")
        }
    }

    /// 旧入口兼容
    private static func postKeyCombo(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        postKeyChord(keyCode: keyCode, modifiers: modifiers)
    }

    /// 正确 chord：先按下修饰键 → 主键 down/up → 松开修饰键。
    /// 旧实现只设 flags 不发修饰键本身，部分 app 会留下 sticky Command，导致 ⌫ 几次后失灵。
    private static func postKeyChord(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        let cmd: CGKeyCode = 0x37      // kVK_Command
        let shift: CGKeyCode = 0x38    // kVK_Shift
        let opt: CGKeyCode = 0x3A      // kVK_Option
        let ctrl: CGKeyCode = 0x3B     // kVK_Control

        func keyDown(_ code: CGKeyCode, flags: CGEventFlags = []) {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true) else { return }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
        func keyUp(_ code: CGKeyCode, flags: CGEventFlags = []) {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) else { return }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }

        let wantCmd = modifiers.contains(.maskCommand)
        let wantShift = modifiers.contains(.maskShift)
        let wantOpt = modifiers.contains(.maskAlternate)
        let wantCtrl = modifiers.contains(.maskControl)

        if wantCmd { keyDown(cmd) }
        if wantShift { keyDown(shift) }
        if wantOpt { keyDown(opt) }
        if wantCtrl { keyDown(ctrl) }
        if wantCmd || wantShift || wantOpt || wantCtrl {
            usleep(4_000)
        }

        keyDown(keyCode, flags: modifiers)
        usleep(12_000)
        keyUp(keyCode, flags: modifiers)
        usleep(4_000)

        if wantCtrl { keyUp(ctrl) }
        if wantOpt { keyUp(opt) }
        if wantShift { keyUp(shift) }
        if wantCmd { keyUp(cmd) }
        usleep(2_000)
    }

    /// 松开 Cmd/Shift/Opt/Ctrl，清 sticky 修饰键
    static func releaseAllModifiers() {
        let src = CGEventSource(stateID: .hidSystemState)
        let codes: [CGKeyCode] = [0x37, 0x38, 0x3A, 0x3B] // cmd shift opt ctrl
        for code in codes {
            if let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) {
                up.flags = []
                up.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - 权限降频警告(避免 spam)

    nonisolated(unsafe) private static var lastWarnTime: TimeInterval = 0
    private static func warnAboutPermission() {
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastWarnTime > 5 {
            MagicLog.event("⚠️  辅助功能未授权 — 请到 系统设置 → 隐私与安全性 → 辅助功能 勾选 MagicPad")
            lastWarnTime = now
        }
    }

    // MARK: - P2-1 加速度曲线

    /// 当前加速档位
    enum AccelerationProfile: String, CaseIterable {
        case off      // 1:1
        case light    // 温和:小移动 1:1,大移动 1.2x
        case medium   // 中等:小移动 1:1,大移动 1.5x
        case strong   // 强:小移动 1:1,大移动 2x

        var factor: Double {
            switch self {
            case .off:    return 0.0
            case .light:  return 0.05
            case .medium: return 0.12
            case .strong: return 0.25
            }
        }

        var label: String {
            switch self {
            case .off:    return "1:1"
            case .light:  return "温和"
            case .medium: return "中等"
            case .strong: return "强"
            }
        }
    }

    /// 全局当前档位(MVP hardcode light,后续接菜单)
    nonisolated(unsafe) static var currentProfile: AccelerationProfile = .light

    /// 加速度曲线 — 简单二次函数
    ///   f(v) = v * (1 + k * |v|)
    /// - 小移动(|v| < 5px):基本 1:1
    /// - 中移动(|v| ≈ 20px):放大 1.2-1.5x
    /// - 大移动(|v| > 50px):放大 2x+
    static func applyAcceleration(dx: Int16, dy: Int16) -> (Int16, Int16) {
        let k = currentProfile.factor
        guard k > 0 else { return (dx, dy) }
        let newDx = Double(dx) * (1.0 + k * Double(abs(Int(dx))) / 10.0)
        let newDy = Double(dy) * (1.0 + k * Double(abs(Int(dy))) / 10.0)
        return (
            Int16(max(-32768, min(32767, Int(newDx.rounded())))),
            Int16(max(-32768, min(32767, Int(newDy.rounded()))))
        )
    }
}
