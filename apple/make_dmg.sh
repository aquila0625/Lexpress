#!/bin/bash
# 打包 macOS 安装用的 DMG，放到仓库根目录的 dist/ 下：./make_dmg.sh
#
# 要让别人从官网下载后能直接打开，需要：
#   1. 钥匙串里有 “Developer ID Application” 证书（在 Xcode › 设置 › 账户 › 管理证书 里添加）；
#   2. 保存过一次公证凭据：
#      xcrun notarytool store-credentials QTranslator --apple-id <你的 Apple ID> --team-id <团队 ID>
# 两样都有时，脚本会用 Developer ID 签名、提交苹果公证并把公证结果钉进 DMG。
# 缺少证书时生成的 DMG 只适合自己或内部测试：别人打开时会被 macOS 拦下。
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' project.yml)
DIST="../dist"
DMG="$DIST/Q-Translator-$VERSION.dmg"
DEVELOPER_ID="${QTRANSLATOR_DEVELOPER_ID:-$(security find-identity -v -p codesigning | awk '/Developer ID Application/ {print $2; exit}')}"
NOTARY_PROFILE="${QTRANSLATOR_NOTARY_PROFILE:-QTranslator}"

./build.sh
APP="build/DerivedData/Build/Products/Release/Q-Translator.app"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
if [[ -n "$DEVELOPER_ID" ]]; then
    # 公证要求开启 hardened runtime 并带可信时间戳
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$STAGE/Q-Translator.app"
    echo "已用 Developer ID 签名"
fi
# 打开 DMG 后看到 App 和“应用程序”文件夹，拖过去就装好了
ln -s /Applications "$STAGE/Applications"

mkdir -p "$DIST"
rm -f "$DMG"
hdiutil create -volname "Q-Translator" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [[ -z "$DEVELOPER_ID" ]]; then
    echo "注意：没有找到 Developer ID Application 证书。这个 DMG 只能自己或内部测试用，"
    echo "      别人下载后 macOS 会提示“无法验证开发者”而不让打开。"
else
    codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "正在提交苹果公证，通常需要几分钟…"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
        echo "已公证"
    else
        echo "注意：没有找到公证凭据 “$NOTARY_PROFILE”，DMG 已签名但未公证，别人打开时仍会被拦下。"
        echo "      先运行：xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <Apple ID> --team-id <团队 ID>"
    fi
fi

echo "已生成 $DMG"
shasum -a 256 "$DMG"
