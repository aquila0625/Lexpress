#!/bin/bash
# 构建 Lexpress.app。用法：./build.sh          只构建到 build/
#                     ./build.sh install  构建并安装到 /Applications
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Lexpress"

APP="build/Lexpress.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lexpress"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "已生成 $APP"

if [[ "${1:-}" == "install" ]]; then
    rm -rf "/Applications/Lexpress.app"
    cp -R "$APP" /Applications/
    # 让系统重新扫描右键“服务”菜单
    /System/Library/CoreServices/pbs -update
    echo "已安装到 /Applications/Lexpress.app"
fi
