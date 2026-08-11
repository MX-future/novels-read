#!/usr/bin/env bash
# scripts/build_macos.sh
# 一键构建 macOS 应用: 自动处理国内 pub 镜像 + Xcode 路径 + flutter build macos
# 用法:
#   bash scripts/build_macos.sh                 # Release 构建
#   bash scripts/build_macos.sh --debug         # Debug 构建
#   bash scripts/build_macos.sh --profile       # Profile 构建
set -euo pipefail

# ---------- 1. pub.dev 国内镜像 (避开代理 502) ----------
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

# ---------- 2. Xcode 完整版路径 (本机 xcode-select 默认指向 CommandLineTools) ----------
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

cd "$(dirname "$0")/.."

echo "==> 环境变量已设置:"
echo "    DEVELOPER_DIR         = ${DEVELOPER_DIR:-(unset)}"
echo "    PUB_HOSTED_URL        = ${PUB_HOSTED_URL}"
echo "    FLUTTER_STORAGE_BASE_URL = ${FLUTTER_STORAGE_BASE_URL}"
echo

echo "==> flutter build macos $*"
flutter build macos "$@"

# ---------- 3. 修复 icns (Xcode 资产目录有时会把 PNG 错误标为 RGBA) ----------
# 用 iconutil 直接从 PNG 重新打包成 icns,确保无 alpha + 包含 1024 大尺寸
APP_PATH="$(find build/macos/Build/Products -name '*.app' -type d | head -1)"
if [ -n "$APP_PATH" ] && [ -d "$APP_PATH/Contents/Resources" ]; then
  ICONSET="$(mktemp -d)/app.iconset"
  mkdir -p "$ICONSET"
  SRC="macos/Runner/Assets.xcassets/AppIcon.appiconset"
  if [ -f "$SRC/app_icon_1024.png" ]; then
    cp "$SRC/app_icon_16.png"   "$ICONSET/icon_16x16.png"
    cp "$SRC/app_icon_32.png"   "$ICONSET/icon_16x16@2x.png"
    cp "$SRC/app_icon_32.png"   "$ICONSET/icon_32x32.png"
    cp "$SRC/app_icon_64.png"   "$ICONSET/icon_32x32@2x.png"
    cp "$SRC/app_icon_128.png"  "$ICONSET/icon_128x128.png"
    cp "$SRC/app_icon_256.png"  "$ICONSET/icon_128x128@2x.png"
    cp "$SRC/app_icon_256.png"  "$ICONSET/icon_256x256.png"
    cp "$SRC/app_icon_512.png"  "$ICONSET/icon_256x256@2x.png"
    cp "$SRC/app_icon_512.png"  "$ICONSET/icon_512x512.png"
    cp "$SRC/app_icon_1024.png" "$ICONSET/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/AppIcon.icns" 2>/dev/null
    echo "==> icns 已用 iconutil 重新打包 (无 alpha, 含 1024@2x)"
  fi
  rm -rf "$ICONSET"
fi