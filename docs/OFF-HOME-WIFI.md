# MagicPad · 离开家里 Wi‑Fi 仍出问题？

**Date**: 2026-08-12  
**Scope**: 同 L2/L3 局域网操控；**不**做公网穿透 / 不绑 Continuity / BT。

---

## 现象

在家里 Wi‑Fi 一切正常，到公司 / 咖啡店 / 手机热点 / 另一套家用路由后出现：

- 扫旧二维码打不开 / 一直转圈  
- 触控断线重连失败  
- HTTPS 录音报证书错误  
- 网页还能开但光标不动（可能是 AX，见文末）

---

## 根因清单（已对照代码）

| ID | 根因 | 修前行为 | 2026-08-12 状态 |
|----|------|----------|-----------------|
| N1 | 客户端写死默认 host（某次家里的 LAN IP） | 无 `?host=` / 异常页时仍连**旧 IP** | **已删**；优先 `location.hostname`，无 host 时弹出连接卡 |
| N2 | 旧 QR / 书签带 `?host=旧IP` | 即使用新 IP 打开页，WS 仍连旧 host | **优先页面真实 host**，忽略陈旧 `?host=` |
| N3 | TLS 证书 SAN 只含生成时的 IP | 换网后 `https://新IP:7879` 证书名不匹配 | **启动 + 缓存命中时** 校验 primary IP ∈ SAN，缺失则 regen |
| N4 | 运行中换 Wi‑Fi 无 path 监听 | 菜单 QR/地址仍显示旧 IP，HTTPS 仍旧 identity | **`LANNetworkMonitor`** + `handleLANChange` → 刷新 IP / 必要时重启 HTTPS |
| N5 | 客人 Wi‑Fi / 客户端隔离 | 手机根本访问不了 Mac | **产品无法绕过**；需同一非隔离 SSID |
| N8 | 主 QR / 复制地址走 HTTPS 自签 | 朋友/新设备 Safari 证书墙，以为打不开 | **H20 主码改回 HTTP :7878**；录音再点页内 HTTPS |
| N9 | 多网卡 QR 印错 IP | en0 以太网与手机 Wi‑Fi 不同网段 | **H20 按默认路由网卡选 IP** |
| N6 | VPN / 代理 | 路由不到 RFC1918 | 关手机/Mac VPN 再试 |
| N7 | AX 丢勾像「网络坏了」 | WS 通但无注入 | rebuild 后重勾辅助功能（`docs/ACCESSIBILITY.md`） |

---

## 换网后正确用法

1. **Mac 与手机同一 Wi‑Fi**（非 Guest / 非 AP isolation）。  
2. 打开菜单栏 **MagicPad** → 看当前 **HTTP/HTTPS 行里的 IP**（应是新网段）。  
3. **重新扫菜单里的动态二维码**（不要用相册旧图 / 旧备忘录链接）。  
4. 录音用 **HTTPS :7879**；仅触控可用 HTTP :7878。  
5. 若 Safari 拦自签：显示详细信息 → 访问此网站。  
6. 光标不动：系统设置 → 隐私与安全性 → 辅助功能 → 勾选 **MagicPad**。

### 手测 30 秒

```bash
# Mac 上
curl -sS http://127.0.0.1:7878/health | python3 -m json.tool | head -30
# 看 ip / ips / ifaces 是否是当前 Wi‑Fi
```

手机浏览器打开：

`http://<health.ip>:7878/?auto=1&host=<health.ip>`

---

## 代码落点

| 文件 | 作用 |
|------|------|
| `LANDetector.swift` | `getifaddrs` 私有 IPv4，优先 en0/en* |
| `LANCert.swift` | SAN 自愈；`revalidateForCurrentLAN()` |
| `LANNetworkMonitor.swift` | `NWPathMonitor` 防抖后通知 |
| `WebSocketServer.swift` | `lanIP` 发布；换网重启 HTTPS |
| `MagicPadClient/index.html` | `resolveInitialHost()`；host drift 切换 |
| `QRImageLoader.swift` | 按当前 URL 动态 QR |

---

## 仍不保证的场景

- 手机蜂窝网 ↔ Mac 家宽（无公网服务，设计如此）  
- 跨 VLAN / 企业隔离  
- 仅 `.local` mDNS（不稳定；永远优先数字 IP）

---

## 回归

```bash
cd /path/to/magicpad
nice -n 19 ./scripts/build_app.sh
# 重启 build/MagicPad.app
./scripts/smoke-all.sh
```
