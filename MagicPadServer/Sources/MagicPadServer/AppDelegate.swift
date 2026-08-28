// AppDelegate.swift
// App 生命周期

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 隐藏 Dock 图标,只保留菜单栏
        NSApp.setActivationPolicy(.accessory)
        MagicLog.app("launched, pid=\(ProcessInfo.processInfo.processIdentifier)")
        MagicLog.app("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // 主动请求辅助功能(弹系统对话框)
        // 如果 user 授权了,AppState 定时器 1s 内变绿
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            EventInjector.requestAccessibilityPermission()
            // 不要在菜单栏第一次 body（可能正泵 runloop）里同步 capture；下一圈再绑端口
            DispatchQueue.main.async {
                WebSocketServer.shared.start()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            Self.showFirstLaunchHintIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if !EventInjector.hasAccessibilityPermission {
                MagicLog.app("AX still false — menu bar shows warning; click 辅助功能")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MagicLog.app("terminating")
        WebSocketServer.shared.stop()
    }

    /// H4-2: 别人拷走 .app 后以为「打不开」——其实在菜单栏。只提示一次。
    @MainActor
    private static func showFirstLaunchHintIfNeeded() {
        let key = "magicpad.didShowLaunchHint"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let alert = NSAlert()
        alert.messageText = "MagicPad 在菜单栏"
        alert.informativeText = """
            没有 Dock 图标，请看屏幕右上角。

            发给别人时：
            1. 对方右键 App → 打开（不要只双击）
            2. 系统设置 → 辅助功能 → 勾选 MagicPad
            3. 手机与这台 Mac 同一 Wi‑Fi，扫菜单里现在的码
            4. 不要用别人家相册里的旧二维码
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
        MagicLog.app("first-launch hint shown")
    }
}
