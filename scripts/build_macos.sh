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
exec flutter build macos "$@"