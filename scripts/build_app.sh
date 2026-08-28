#!/bin/bash
# build_app.sh — 把 SwiftPM .build 的裸 binary 打包成 macOS .app bundle
#
# 用法:
#   ./scripts/build_app.sh              # 全量：换 binary + HTML + 重签（常掉 AX）
#   ./scripts/build_app.sh --html-only  # H27: 只换 Resources/index.html，不换 binary、不重签、不杀进程
# 输出: build/MagicPad.app
# 安装: cp -R build/MagicPad.app /Applications/

set -e

APP_NAME="MagicPad"
APP_DISPLAY_NAME="MagicPad"
BUNDLE_ID="app.magicpad.server"
VERSION="0.1.0"
HTML_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --html-only|-H) HTML_ONLY=1 ;;
        --help|-h)
            echo "Usage: $0 [--html-only]"
            exit 0
            ;;
    esac
done

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_BINARY="$PROJECT_ROOT/MagicPadServer/.build/arm64-apple-macosx/debug/MagicPadServer"
APP_DIR="$PROJECT_ROOT/build/$APP_NAME.app"
INDEX_SRC="$PROJECT_ROOT/MagicPadClient/index.html"

if [ ! -f "$INDEX_SRC" ]; then
    echo "❌ missing MagicPadClient/index.html — refuse to package empty client"
    exit 1
fi

# H27: HTML-only — keep running binary + AX checkbox. Phone H11 reloads on htmlRev mismatch.
if [ "$HTML_ONLY" = "1" ]; then
    if [ ! -f "$APP_DIR/Contents/MacOS/MagicPadServer" ]; then
        echo "❌ $APP_DIR missing — run a full build first"
        exit 1
    fi
    mkdir -p "$APP_DIR/Contents/Resources"
    cp "$INDEX_SRC" "$APP_DIR/Contents/Resources/index.html"
    echo "📦 H27 html-only → Resources/index.html ($(wc -c < "$INDEX_SRC" | tr -d ' ') bytes)"
    echo "   no binary copy · no xattr · no codesign · no pkill"
    echo "✅ $APP_DIR HTML updated (app stays running; phone auto-reloads on htmlRev)"
    exit 0
fi

if [ ! -f "$SOURCE_BINARY" ]; then
    echo "❌ source binary not found: $SOURCE_BINARY"
    echo "   run 'swift build' in MagicPadServer/ first"
    exit 1
fi

# H7-2: 原地更新，不要 rm -rf 整包（每次删包重签几乎必掉辅助功能）
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 复制 binary
cp "$SOURCE_BINARY" "$APP_DIR/Contents/MacOS/MagicPadServer"
chmod +x "$APP_DIR/Contents/MacOS/MagicPadServer"

# 内嵌客户端 HTML(多设备/无源码路径时仍可打开操控页 — P0-9/P1-4)
cp "$INDEX_SRC" "$APP_DIR/Contents/Resources/index.html"
echo "📦 bundled MagicPadClient/index.html → Resources/ ($(wc -c < "$INDEX_SRC" | tr -d ' ') bytes)"

# On-device Whisper (Core ML / ANE). Prefer base; keep tiny as fallback.
# vendor/ is gitignored; Application Support cache is a local seed.
bundle_whisper_variant() {
    local name="$1"
    local src="$PROJECT_ROOT/vendor/whisper/$name"
    local cache="$HOME/Library/Application Support/MagicPad/whisper/$name"
    if [ ! -d "$src/TextDecoder.mlmodelc" ] && [ -d "$cache/TextDecoder.mlmodelc" ]; then
        mkdir -p "$PROJECT_ROOT/vendor/whisper"
        rsync -a --delete "$cache/" "$src/"
        echo "📦 seeded vendor/whisper/$name from local cache"
    fi
    if [ -d "$src/TextDecoder.mlmodelc" ]; then
        mkdir -p "$APP_DIR/Contents/Resources/whisper"
        rsync -a --delete "$src" "$APP_DIR/Contents/Resources/whisper/"
        echo "📦 bundled $name → Resources/whisper/"
        return 0
    fi
    return 1
}
BUNDLED_WHISPER=0
if bundle_whisper_variant openai_whisper-base; then
    BUNDLED_WHISPER=1
    bundle_whisper_variant openai_whisper-tiny || true
elif bundle_whisper_variant openai_whisper-tiny; then
    BUNDLED_WHISPER=1
fi
if [ "$BUNDLED_WHISPER" != "1" ]; then
    echo "⚠️  Whisper not in vendor/ — app will download on first 听写" >&2
fi

# 写 Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MagicPadServer</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_DISPLAY_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>MagicPad 需要访问本地网络以发现和连接你的手机。</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>MagicPad 在 Mac 上把语音转成文字，仅用于剪贴板直达，不连接任何 AI 云服务。</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>MagicPad 使用 Mac 麦克风做可选听写转写；文字只进剪贴板，不绑定任何 AI agent。</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
PLIST

# 写 PkgInfo
printf "APPL????" > "$APP_DIR/Contents/PkgInfo"

# === 生成 QR PNG 到 .app Resources ===
# 否则每次 build_app.sh 都会清空 Resources,QR 就丢了
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -f "$SCRIPT_DIR/generate_qr.py" ]; then
    echo ""
    echo "🔄 重新生成 QR..."
    python3 "$SCRIPT_DIR/generate_qr.py" --auto 2>&1 | tail -3
fi

# 标 quarantine(避免 GateKeeper 拦截)
xattr -cr "$APP_DIR" 2>/dev/null || true

# codesign(ad-hoc + 稳定 identifier；先签 binary 再签 bundle)
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR/Contents/MacOS/MagicPadServer" 2>&1 | tail -2 || true
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_DIR" 2>&1 | tail -3 || echo "(ad-hoc codesign failed, may need manual signing)"

echo ""
echo "✅ $APP_DIR 已生成"
echo ""
ls -la "$APP_DIR"
echo ""
ls -la "$APP_DIR/Contents"
echo ""
echo "用法:"
echo "  open '$APP_DIR'                            # 启动"
echo "  cp -R '$APP_DIR' /Applications/             # 装到 Applications"
echo ""
echo "⚠️  首次或换路径后需勾辅助功能。原地更新 binary 尽量保勾；若 /health ax=false 再重勾。"
