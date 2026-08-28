// MagicPadServer.swift
// 入口 + 菜单栏 UI (Control Center 风格)
//
// 设计: 仿 macOS 控制中心
//   - 模块化 (每个功能是独立 widget, 圆角矩形, 磨砂背景)
//   - 大尺寸 tappable surface
//   - Tinted state (颜色编码 on/off: 蓝/灰)
//   - Material 背景 (.regularMaterial) 自适应明暗
//   - 统一 spacing rhythm (8/12/16)
//   - 顶部 hero(大 QR 居中,带 caption), 下方 2x2 模块网格
//   - 底部状态条(简化)

import SwiftUI
import AppKit

@main
struct MagicPadServerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var server = WebSocketServer.shared
    @ObservedObject private var appState = AppState.shared
    /// Menu QR: bump when CoreImage finishes off-main. Not tied to httpsReady.
    @State private var qrEpoch = 0

    var body: some Scene {
        MenuBarExtra {
            // 整体宽度 ~360pt,高度自适应
            VStack(spacing: 0) {
                // One healthLAN window for QR pixels + caption + HTTP/HTTPS/IPs/网卡.
                // Runtime LANDetector.ip — never a baked home address. Actions re-read.
                let lan = InstallEnvironment.healthLAN
                let qrURL = QRImageLoader.mobileURL(from: lan)
                // ==========================================
                // Header — 简洁品牌
                // ==========================================
                HStack(alignment: .firstTextBaseline) {
                    Text("MagicPad")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(-0.2)
                    Spacer()
                    Text("v0.1.0")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)

                Divider().opacity(0.4)

                // ==========================================
                // Hero — 大 QR 扫码
                // ==========================================
                VStack(spacing: 10) {
                    // 动态 QR：运行时 LANDetector.ip（healthLAN.mobileURL）。主码永远 HTTP :7878。
                    // httpsReady 只改下面 HTTPS 状态行，不得改写主码（朋友/新设备要能打开）。
                    // Body: peek(matching:) only — never CoreImage / never baked qr-mobile.png on MainActor.
                    // Do not onChange(httpsReady). Menu body peeks; CoreImage stays off-main.
                    if let qrImage = QRImageLoader.peek(matching: qrURL) {
                        Image(nsImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(width: 300, height: 300)
                            .padding(12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
                            .id("\(qrURL)|\(qrEpoch)") // not lanIP/httpsReady — HTTP :7878 pixels stay
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 64, weight: .ultraLight))
                                .foregroundStyle(.tertiary)
                            Text("正在生成 QR…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 300, height: 300)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Text(qrURL)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                    Text("同一 Wi‑Fi 才能打开 · 别人家/客人网不行 · 勿用相册旧码")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    Text("扫码打开 · HTTP :7878（新设备/朋友）")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 18)
                .padding(.bottom, 14)
                .onAppear { QRImageLoader.prepareOffMain() }
                .onReceive(NotificationCenter.default.publisher(for: QRImageLoader.readyNotification)) { _ in
                    qrEpoch += 1
                }
                .onChange(of: server.lanIP) { _ in
                    // Leave-home Wi‑Fi / DHCP: same healthLAN snapshot as caption.
                    // Path queue already invalidateForLANChange+CoreImage. Do not hook httpsReady.
                    let lan = InstallEnvironment.healthLAN
                    let url = QRImageLoader.mobileURL(from: lan)
                    if QRImageLoader.peek(matching: url) == nil {
                        QRImageLoader.prepareOffMain()
                    }
                }

                // ==========================================
                // 2x2 模块网格 — 控制中心风格
                // ==========================================
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    // 模块 1: 复制完整地址
                    ModuleButton(
                        icon: "doc.on.doc.fill",
                        label: "复制地址",
                        sublabel: "HTTP 先打开",
                        tint: .blue,
                        action: {
                            let lan = InstallEnvironment.healthLAN
                            let url = QRImageLoader.mobileURL(from: lan)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                            MagicLog.menu("copied URL")
                        }
                    )

                    // 模块 2: 复制 IP
                    ModuleButton(
                        icon: "network",
                        label: "复制 IP",
                        sublabel: "仅 IP",
                        tint: .gray,
                        action: {
                            let lan = InstallEnvironment.healthLAN
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(lan.ip, forType: .string)
                            MagicLog.menu("copied IP")
                        }
                    )

                    // 模块 3: 辅助功能(用 AppState 实时同步)
                    ModuleButton(
                        icon: appState.hasAccessibility ? "lock.open.fill" : "lock.fill",
                        label: "辅助功能",
                        sublabel: appState.hasAccessibility ? "已授权" : "未授权",
                        tint: appState.hasAccessibility ? .green : .orange,
                        action: {
                            EventInjector.openAccessibilitySettings()
                        }
                    )

                    // 模块 4: 服务器控制
                    ModuleButton(
                        icon: server.isRunning ? "pause.circle.fill" : "play.circle.fill",
                        label: server.isRunning ? "停止" : "启动",
                        sublabel: "服务器",
                        tint: server.isRunning ? .red : .blue,
                        action: {
                            if server.isRunning {
                                WebSocketServer.shared.stop()
                            } else {
                                WebSocketServer.shared.start()
                            }
                        }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

                Divider().opacity(0.4)

                // ==========================================
                // 状态条 — 紧凑 monospace
                // ==========================================
                VStack(alignment: .leading, spacing: 6) {
                    StatusLine(label: "HTTP",
                               value: lan.httpUrl)
                    // httpsReady flips this caption only. Main QR above stays HTTP :7878.
                    StatusLine(label: "HTTPS",
                               value: server.httpsReady
                                   ? "\(lan.httpsUrl) (mic)"
                                   : "未就绪 \(LANCert.statusError.isEmpty ? "—" : LANCert.statusError)",
                               secondary: true)
                    StatusLine(label: "IPs",
                               value: lan.ips.isEmpty ? lan.ip : lan.ips.joined(separator: " · "),
                               secondary: true)
                    StatusLine(label: "网卡",
                               value: lan.routeIface.isEmpty ? "—" : lan.routeIface,
                               secondary: true)
                    StatusLine(label: "AX",
                               value: appState.hasAccessibility
                                   ? "已授权"
                                   : "未授权 · 点「辅助功能」打开设置",
                               secondary: appState.hasAccessibility)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                Divider().opacity(0.4)

                // ==========================================
                // 底部 — 关于 + 退出
                // ==========================================
                HStack {
                    Button {
                        showAbout()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                            Text("关于")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showShareHelp()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 10))
                            Text("发给别人")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        openCertDirectory()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                            Text("打开证书目录")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(LANCert.supportDir.path)

                    Spacer()

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "power")
                                .font(.system(size: 10))
                            Text("退出")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("q", modifiers: [.command])
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
            }
            .frame(width: 380)
        } label: {
            // H13: AX 掉勾时菜单栏立刻变警告，不用点开才发现光标没反应
            if !appState.hasAccessibility {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: server.isRunning
                      ? "cursorarrow.click.2"
                      : "cursorarrow")
                    .symbolRenderingMode(.multicolor)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - ModuleButton (控制中心风格的模块按钮)

struct ModuleButton: View {
    let icon: String
    let label: String
    let sublabel: String
    let tint: Tint
    let action: () -> Void

    enum Tint {
        case blue, green, orange, red, gray

        var color: Color {
            switch self {
            case .blue: return .blue
            case .green: return .green
            case .orange: return .orange
            case .red: return .red
            case .gray: return .gray
            }
        }
    }

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(tint.color)
                    Spacer()
                }
                Spacer().frame(height: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(sublabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 80)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isHovered ? tint.color.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.color.opacity(isHovered ? 0.4 : 0.0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - StatusLine (状态行)

struct StatusLine: View {
    let label: String
    let value: String
    var secondary: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .frame(width: 38, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(secondary ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

// MARK: - About / cert dir

@MainActor
private func showAbout() {
    let lan = InstallEnvironment.healthLAN
    let alert = NSAlert()
    alert.messageText = "MagicPad"
    alert.informativeText = """
        iPhone 触控板 + 语音直达 Mac。

        版本 0.1.0
        手机: \(lan.httpUrl)
        HTTPS: \(lan.httpsUrl)
        """
    alert.alertStyle = .informational
    alert.addButton(withTitle: "好")
    alert.runModal()
}

@MainActor
private func showShareHelp() {
    let alert = NSAlert()
    alert.messageText = "发给别人"
    alert.informativeText = """
        对方必须在自己的 Mac 上打开 MagicPad（菜单栏，无 Dock 图标）。

        · 右键 App → 打开（Gatekeeper 会拦双击）
        · 若提示已损坏：终端 xattr -cr 后再打开
        · 勾选辅助功能
        · 扫对方菜单里现在的码，同一 Wi‑Fi
        · 不要发你家旧二维码；外网/蜂窝打不开是设计如此
        """
    alert.alertStyle = .informational
    alert.addButton(withTitle: "好")
    alert.runModal()
    MagicLog.menu("share help")
}

/// Reveal ~/Library/Application Support/MagicPad/ (p12 / cer / pem).
@MainActor
private func openCertDirectory() {
    let dir = LANCert.supportDir
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    NSWorkspace.shared.open(dir)
    MagicLog.menu("open cert dir \(dir.path)")
}
