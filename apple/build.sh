#!/bin/bash
# 构建 macOS 版 Q-Translator.app。用法：./build.sh          只构建到 build/
#                                  ./build.sh install  构建并安装到 /Applications
# 需要 Xcode 和 XcodeGen（brew install xcodegen）。
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate --quiet
# -quiet 模式下 xcodebuild 会多打两行无害的 “exit code 0” 提示，过滤掉
set +e
xcodebuild -project QTranslator.xcodeproj -scheme QTranslator-macOS -configuration Release \
    -derivedDataPath build/DerivedData -quiet build 2>&1 | grep -v "produced no further output"
status=${PIPESTATUS[0]}
set -e
if [[ $status -ne 0 ]]; then
    echo "构建失败"
    exit "$status"
fi
APP="build/DerivedData/Build/Products/Release/Q-Translator.app"
echo "已生成 $APP"

if [[ "${1:-}" == "install" ]]; then
    rm -rf "/Applications/Q-Translator.app"
    cp -R "$APP" /Applications/
    # 让系统重新扫描右键“服务”菜单
    /System/Library/CoreServices/pbs -update
    echo "已安装到 /Applications/Q-Translator.app"
fi
