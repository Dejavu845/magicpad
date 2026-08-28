#!/usr/bin/env python3
"""
generate_qr.py — 生成 MagicPad 手机连接二维码（构建期 PNG，运行时菜单不依赖此 IP）

用法:
    python3 scripts/generate_qr.py
    python3 scripts/generate_qr.py --auto
    python3 scripts/generate_qr.py 10.0.0.12 --output /path/to/qr.png
    python3 scripts/generate_qr.py --http   # force HTTP :7878
    python3 scripts/generate_qr.py --print-only --auto  # URL only, no PNG

运行时菜单 QR 由 QRImageLoader + LANDetector.ip 现场生成，不读这里烤进去的 IP。
本脚本同样按默认路由网卡探测，禁止写死家宽地址。
H20: 默认 HTTP :7878（新设备能打开）。--https 才生成自签 :7879。
输出默认: build/MagicPad.app/Contents/Resources/qr-mobile.png
"""

import os
import sys
import argparse
import subprocess
import re
from pathlib import Path


SKIP_PREFIXES = ("lo", "awdl", "llw", "utun", "bridge", "veth", "docker", "vmnet", "ap")


def is_private(ip: str) -> bool:
    parts = ip.split(".")
    if len(parts) != 4:
        return False
    try:
        a, b = int(parts[0]), int(parts[1])
    except ValueError:
        return False
    if a == 192 and b == 168:
        return True
    if a == 10:
        return True
    if a == 172 and 16 <= b <= 31:
        return True
    return False


def default_route_interface() -> str | None:
    """`route -n get default` → interface name. Build-time only; app does this off-main."""
    try:
        out = subprocess.check_output(
            ["/sbin/route", "-n", "get", "default"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
    except Exception:
        return None
    for raw in out.splitlines():
        line = raw.strip()
        if line.startswith("interface:"):
            name = line.split(":", 1)[1].strip()
            return name or None
    return None


def named_private_ipv4() -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    try:
        out = subprocess.check_output(
            ["/sbin/ifconfig"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
    except Exception:
        return found
    iface: str | None = None
    for line in out.splitlines():
        if line and not line[0].isspace() and ":" in line:
            iface = line.split(":", 1)[0]
            continue
        if not iface:
            continue
        if any(iface.startswith(p) for p in SKIP_PREFIXES):
            continue
        parts = line.split()
        if "inet" not in parts:
            continue
        idx = parts.index("inet")
        if idx + 1 >= len(parts):
            continue
        ip = parts[idx + 1]
        if ip != "127.0.0.1" and is_private(ip):
            found.append((iface, ip))

    def rank(name: str) -> int:
        if name == "en0":
            return 0
        if name == "en1":
            return 1
        if name.startswith("en"):
            return 2
        return 10

    found.sort(key=lambda item: rank(item[0]))
    return found


def detect_ip() -> tuple[str, str]:
    """本机局域网 IP：默认路由网卡优先，其次 en0/en1/en*。从不写死家宽地址。

    Returns (ip, iface). Build-time only — MagicPad.app menu ignores the PNG.
    """
    named = named_private_ipv4()
    iface = default_route_interface()
    if iface:
        for name, ip in named:
            if name == iface:
                return ip, name
    for want in ("en0", "en1"):
        for name, ip in named:
            if name == want:
                return ip, name
    for name, ip in named:
        if name.startswith("en"):
            return ip, name
    if named:
        return named[0][1], named[0][0]
    return "127.0.0.1", "?"


_HARDCODED_LAN_IP = re.compile(
    r"(?:192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3})"
)


def refuse_baked_home_ip() -> None:
    """QR must come from the live LAN IP. Do not embed any private IPv4 literal."""
    here = Path(__file__).resolve()
    root = here.parent.parent
    runtime = [
        root / "MagicPadServer/Sources/MagicPadServer/QRImageLoader.swift",
        root / "MagicPadServer/Sources/MagicPadServer/LANDetector.swift",
        root / "MagicPadServer/Sources/MagicPadServer/InstallEnvironment.swift",
        root / "MagicPadServer/Sources/MagicPadServer/LANNetworkMonitor.swift",
        root / "MagicPadServer/Sources/MagicPadServer/MagicPadServer.swift",
    ]
    for path in runtime:
        if not path.is_file():
            continue
        body = path.read_text(encoding="utf-8")
        if _HARDCODED_LAN_IP.search(body):
            print(f"❌ {path.name} must not bake a LAN address (runtime QR uses LANDetector.ip)", file=sys.stderr)
            sys.exit(1)
    qr_loader = root / "MagicPadServer/Sources/MagicPadServer/QRImageLoader.swift"
    if qr_loader.is_file():
        qbody = qr_loader.read_text(encoding="utf-8")
        start = qbody.find("static func mobileURL(")
        end = qbody.find("static func mobileHTTPSURL()")
        chunk = qbody[start:end] if start >= 0 and end > start else ""
        if "https://" in chunk:
            print("❌ QRImageLoader.mobileURL must not encode https (friends need :7878)", file=sys.stderr)
            sys.exit(1)
        if "invalidateForLANChange" not in qbody:
            print("❌ QRImageLoader.invalidateForLANChange required (LAN dump; httpsReady stays no-op)", file=sys.stderr)
            sys.exit(1)
        if "peek(matching" not in qbody:
            print("❌ QRImageLoader.peek(matching:) required (menu caption + pixels one URL)", file=sys.stderr)
            sys.exit(1)
        if "main load is peek only" not in qbody:
            print("❌ QRImageLoader.load() on main must peek only (no CoreImage / no prepareOffMain)", file=sys.stderr)
            sys.exit(1)
        if "peek(matching: mobileURL())" not in qbody:
            print("❌ QRImageLoader.load() on main must peek(matching: mobileURL())", file=sys.stderr)
            sys.exit(1)
        if "LANDetector.mobileHTTPURL" in chunk:
            print("❌ QRImageLoader.mobileURL must stay on the passed healthLAN snapshot", file=sys.stderr)
            sys.exit(1)
    menu = root / "MagicPadServer/Sources/MagicPadServer/MagicPadServer.swift"
    if menu.is_file():
        mbody = menu.read_text(encoding="utf-8")
        if "onChange(of: server.httpsReady)" in mbody:
            print("❌ menu QR must not onChange httpsReady (main code stays HTTP :7878)", file=sys.stderr)
            sys.exit(1)
        if "QRImageLoader.load(" in mbody:
            print("❌ menu QR must peek/prepareOffMain, not load() on SwiftUI body", file=sys.stderr)
            sys.exit(1)
        if "peek(matching:" not in mbody:
            print("❌ menu QR must peek(matching:) so caption and pixels share one URL", file=sys.stderr)
            sys.exit(1)
        if "mobileURL(from:" not in mbody:
            print("❌ menu QR URL must come from healthLAN (LANDetector.ip at runtime)", file=sys.stderr)
            sys.exit(1)
        if mbody.count("mobileURL(from:") < 3:
            print("❌ menu QR caption + copy + onChange must share mobileURL(from: healthLAN)", file=sys.stderr)
            sys.exit(1)
        extra_idx = mbody.find("MenuBarExtra")
        extra_chunk = mbody[extra_idx:extra_idx + 2200] if extra_idx >= 0 else ""
        if "let lan = InstallEnvironment.healthLAN" not in extra_chunk:
            print("❌ menu must snapshot healthLAN once for QR + HTTP/HTTPS/IPs status", file=sys.stderr)
            sys.exit(1)
        if "let qrURL = QRImageLoader.mobileURL(from: lan)" not in extra_chunk:
            print("❌ menu QR URL must be one mobileURL(from: healthLAN) for pixels + caption", file=sys.stderr)
            sys.exit(1)
        if '.id("\\(qrURL)|\\(qrEpoch)")' not in mbody:
            print("❌ menu QR id must be qrURL|qrEpoch (not lanIP/httpsReady)", file=sys.stderr)
            sys.exit(1)
        if "setString(LANDetector.ip" in mbody:
            print("❌ copy IP must use healthLAN.ip (same struct as QR /health)", file=sys.stderr)
            sys.exit(1)
        if "setString(lan.ip" not in mbody:
            print("❌ copy IP must use healthLAN.ip", file=sys.stderr)
            sys.exit(1)
    monitor = root / "MagicPadServer/Sources/MagicPadServer/LANNetworkMonitor.swift"
    if monitor.is_file():
        nbody = monitor.read_text(encoding="utf-8")
        if "QRImageLoader.load(" in nbody:
            print("❌ LANNetworkMonitor must peek + prepareOffMain (never load() / CoreImage on main)", file=sys.stderr)
            sys.exit(1)
        if "liveProbe" not in nbody:
            print("❌ LANNetworkMonitor quiet path must liveProbe() without flushing the /health pin", file=sys.stderr)
            sys.exit(1)
        if "availableInterfaces" not in nbody:
            print("❌ LANNetworkMonitor must watch NWPath preferred iface (dual-home default route)", file=sys.stderr)
            sys.exit(1)
        if "invalidateForLANChange" not in nbody:
            print("❌ LANNetworkMonitor must invalidateForLANChange (force regenerate; httpsReady no-op)", file=sys.stderr)
            sys.exit(1)
        if "mobileURL(from:" not in nbody:
            print("❌ LANNetworkMonitor LAN QR URL must come from healthLAN (LANDetector.ip)", file=sys.stderr)
            sys.exit(1)
        if nbody.count("InstallEnvironment.capture(") < 2:
            print("❌ LANNetworkMonitor must capture off-main on prime AND on LAN publish", file=sys.stderr)
            sys.exit(1)
        if "never on main" not in nbody:
            print("❌ LANNetworkMonitor must keep route/scutil off-main before handleLANChange", file=sys.stderr)
            sys.exit(1)
    env = root / "MagicPadServer/Sources/MagicPadServer/InstallEnvironment.swift"
    if env.is_file():
        ebody = env.read_text(encoding="utf-8")
        if "htmlOverride = true" not in ebody:
            print("❌ capture must default htmlFromBundle on MainActor (no path lookup)", file=sys.stderr)
            sys.exit(1)
        if "static var healthLAN" not in ebody:
            print("❌ InstallEnvironment.healthLAN required (/health + QR one struct)", file=sys.stderr)
            sys.exit(1)
        if "ips.prefix(8)" not in ebody:
            print("❌ healthLAN ips must cap at 8", file=sys.stderr)
            sys.exit(1)
        if ebody.count("cached = snap") != 1:
            print("❌ only capture() may write InstallEnvironment cache (current overlays live)", file=sys.stderr)
            sys.exit(1)
        if "no path lookup on main" not in ebody:
            print("❌ capture/snapshot must not resolvedIndexHTMLPath on MainActor", file=sys.stderr)
            sys.exit(1)
    detector = root / "MagicPadServer/Sources/MagicPadServer/LANDetector.swift"
    if detector.is_file():
        dbody = detector.read_text(encoding="utf-8")
        if "func liveProbe" not in dbody:
            print("❌ LANDetector.liveProbe required (quiet NWPath must not flush healthFields)", file=sys.stderr)
            sys.exit(1)
        if "runTool refused on main" not in dbody:
            print("❌ LANDetector.runTool must refuse on main (route/scutil freeze)", file=sys.stderr)
            sys.exit(1)
        if "routeAlive" not in dbody:
            print("❌ LANDetector.makeHealth must drop a down route nic (advertised routeIface owns ip)", file=sys.stderr)
            sys.exit(1)
        if "magicpad.lan.route" not in dbody:
            print("❌ LANDetector.refreshOffMain must serialize route/scutil off-main", file=sys.stderr)
            sys.exit(1)
        if "refreshOffMainBody refused on main" not in dbody:
            print("❌ LANDetector.refreshOffMainBody must refuse on main (no route/scutil freeze)", file=sys.stderr)
            sys.exit(1)
        if "magicpad.lan.httpReaderPin" not in dbody:
            print("❌ LANDetector HTTP-worker pin required (/health ip vs httpUrl during AX)", file=sys.stderr)
            sys.exit(1)
        if "Main never pins" not in dbody:
            print("❌ LANDetector HTTP pin must skip MainActor (menu / handleLANChange live)", file=sys.stderr)
            sys.exit(1)
        if "health cap 8" not in dbody:
            print("❌ LANDetector.makeHealth must cap ips/ifaces at 8", file=sys.stderr)
            sys.exit(1)


def main():
    refuse_baked_home_ip()
    parser = argparse.ArgumentParser()
    parser.add_argument("ip", nargs="?", help="Mac 局域网 IP（默认：默认路由网卡）")
    parser.add_argument("--port", type=int, default=None, help="覆盖端口")
    parser.add_argument("--http", action="store_true", help="强制 HTTP:7878（触控默认）")
    parser.add_argument("--https", action="store_true", help="强制 HTTPS:7879")
    parser.add_argument("--output", help="输出 PNG 路径")
    parser.add_argument("--auto", action="store_true", help="QR 内容带 ?auto=1(iOS 端会自动连)")
    parser.add_argument("--print-only", action="store_true", help="只打印 URL，不写 PNG（运行时菜单仍不读此 IP）")
    args = parser.parse_args()

    if args.ip:
        ip, iface = args.ip, "cli"
    else:
        ip, iface = detect_ip()
    print(f"📡 Mac IP: {ip} iface={iface} (runtime menu QR ignores this PNG; uses LANDetector.ip)")
    if not ip or ip == "127.0.0.1":
        print("⚠️  no private LAN IP detected — runtime menu still uses LANDetector.ip, not this PNG")

    scheme = "http"
    port = 7878
    if args.https and not args.http:
        scheme, port = "https", args.port or 7879
        print("ℹ️  --https 自签 :7879（仅录音备用；主码请不要发这个）")
    else:
        scheme, port = "http", args.port or 7878
        print("ℹ️  主 QR 用 HTTP :7878（新设备/朋友先能打开；录音再上 HTTPS）")

    url = f"{scheme}://{ip}:{port}/"
    if args.auto:
        url += f"?auto=1&host={ip}"
    print(f"🔗 QR URL: {url}")
    if scheme != "http" and not args.https:
        print("❌ main QR must be http (friends need :7878)", file=sys.stderr)
        sys.exit(1)
    if args.print_only:
        return

    try:
        import qrcode
    except ImportError:
        print("❌ 缺 qrcode 库: pip3 install qrcode[pil]")
        sys.exit(1)

    if args.output:
        out = args.output
    else:
        out = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "build", "MagicPad.app", "Contents", "Resources", "qr-mobile.png",
        )

    os.makedirs(os.path.dirname(out), exist_ok=True)

    qr = qrcode.QRCode(version=1, box_size=10, border=4,
                       error_correction=qrcode.constants.ERROR_CORRECT_M)
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(fill_color="#000", back_color="#fff")
    img.save(out)
    print(f"✅ QR saved: {out} ({os.path.getsize(out)} bytes)")


if __name__ == "__main__":
    main()
