// AppState.swift
// 全局可观察的 App 状态(权限等)
// 定时器每 1 秒查一次 AXIsProcessTrusted,授权变化立刻反映到 UI

import Foundation
import AppKit

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var hasAccessibility: Bool = false

    private var timer: Timer?

    private init() {
        refresh()
        startPolling()
    }

    func refresh() {
        let new = EventInjector.hasAccessibilityPermission
        if new != hasAccessibility {
            MagicLog.event("AX 权限变化: \(hasAccessibility) → \(new)")
        }
        hasAccessibility = new
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    // 注: 单例永生,不需要 deinit
    // Swift 6 限制 @MainActor 隔离属性无法在 nonisolated deinit 访问
}
