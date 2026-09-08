#!/usr/bin/env bash
#
# TypeX 完全清理重装脚本
# 用于解决设置界面缓存导致的UI不更新问题
#

set -e

PACKAGE_ID="com.lindo.typex"
DEB_PATH="$1"

if [[ -z "$DEB_PATH" ]]; then
    echo "用法: $0 <deb文件路径>"
    echo "示例: $0 packages/ios16/com.lindo.typex_2.7.36_ios16_iphoneos-arm64e.deb"
    exit 1
fi

if [[ ! -f "$DEB_PATH" ]]; then
    echo "错误: 找不到 deb 文件: $DEB_PATH"
    exit 1
fi

echo "==> 开始完全清理重装 TypeX..."

# 检查是否通过 USB 连接设备
if ! command -v iproxy &> /dev/null; then
    echo "警告: 未找到 iproxy，将尝试直接 SSH 连接"
    SSH_CMD="ssh root@localhost"
    SCP_CMD="scp"
else
    echo "提示: 请确保已运行 'iproxy 2222 22' 将设备 SSH 端口转发到本地 2222"
    SSH_CMD="ssh -p 2222 root@localhost"
    SCP_CMD="scp -P 2222"
fi

echo ""
echo "==> 步骤 1/6: 检查设备连接..."
if ! $SSH_CMD "echo '连接成功'" 2>/dev/null; then
    echo "错误: 无法连接到设备"
    echo ""
    echo "请确保："
    echo "  1. 设备已越狱并启用 SSH"
    echo "  2. 已运行 'iproxy 2222 22'（如果通过 USB）"
    echo "  3. 或者设备和电脑在同一 WiFi 网络（修改脚本中的 SSH_CMD）"
    exit 1
fi

echo ""
echo "==> 步骤 2/6: 卸载旧版本..."
$SSH_CMD "dpkg -r $PACKAGE_ID 2>/dev/null || echo '(未安装旧版本)'"

echo ""
echo "==> 步骤 3/6: 清理设置缓存和残留文件..."
$SSH_CMD "rm -rf /Library/PreferenceBundles/TypeXPrefs.bundle"
$SSH_CMD "rm -f /Library/PreferenceLoader/Preferences/TypeX.plist"
$SSH_CMD "rm -f /var/mobile/Library/Preferences/com.lindo.typex.plist"
$SSH_CMD "killall -9 Preferences 2>/dev/null || true"
$SSH_CMD "killall -9 cfprefsd 2>/dev/null || true"

echo ""
echo "==> 步骤 4/6: 上传并安装新版本..."
$SCP_CMD "$DEB_PATH" root@localhost:/tmp/typex.deb
$SSH_CMD "dpkg -i /tmp/typex.deb && rm /tmp/typex.deb"

echo ""
echo "==> 步骤 5/6: 验证安装..."
INSTALLED_VERSION=$($SSH_CMD "dpkg -s $PACKAGE_ID 2>/dev/null | grep '^Version:' | awk '{print \$2}' || echo 'FAILED'")
if [[ "$INSTALLED_VERSION" == "FAILED" ]]; then
    echo "错误: 安装失败"
    exit 1
fi
echo "已安装版本: $INSTALLED_VERSION"

echo ""
echo "==> 步骤 6/6: 重启 SpringBoard..."
$SSH_CMD "killall -9 SpringBoard"

echo ""
echo "✅ 完成！请等待设备重新加载后打开 设置 > TypeX > Customization 查看新UI"
echo ""
echo "如果仍然看不到新UI，请尝试："
echo "  1. 完全重启设备（不是注销）"
echo "  2. 检查设置语言是否为中文（中文显示）或英文"
echo "  3. 运行 uicache 刷新："
echo "     ssh root@localhost 'uicache'"
