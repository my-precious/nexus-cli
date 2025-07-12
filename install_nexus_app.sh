#!/bin/bash

# Nexus CLI 应用程序安装脚本
# 将应用程序复制到桌面并设置权限

echo "🚀 正在安装 Nexus CLI 自动重启应用程序..."

# 检查应用程序是否存在
if [ ! -d "Nexus CLI Restart.app" ]; then
    echo "❌ 错误: 找不到应用程序包"
    echo "请确保在正确的目录中运行此脚本"
    exit 1
fi

# 复制到桌面
DESKTOP_PATH="$HOME/Desktop"
APP_NAME="Nexus CLI Restart.app"
TARGET_PATH="$DESKTOP_PATH/$APP_NAME"

echo "📁 正在复制应用程序到桌面..."

# 如果桌面已存在同名应用，先删除
if [ -d "$TARGET_PATH" ]; then
    echo "⚠️ 桌面已存在同名应用程序，正在删除..."
    rm -rf "$TARGET_PATH"
fi

# 复制应用程序
cp -R "Nexus CLI Restart.app" "$DESKTOP_PATH/"

# 设置权限
chmod +x "$TARGET_PATH/Contents/MacOS/nexus_restart"

echo "✅ 应用程序安装完成！"
echo ""
echo "📋 使用说明:"
echo "1. 双击桌面上的 'Nexus CLI Restart' 图标启动"
echo "2. 确保已编译 CLI: cargo build --release"
echo "3. 确保节点文件存在: ~/.nexus/nodes.txt"
echo ""
echo "🎉 现在您可以在桌面上找到 Nexus CLI 自动重启应用程序了！" 