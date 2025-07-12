#!/bin/bash

# 创建简单的应用程序图标
# 使用 macOS 内置图标作为占位符

echo "🎨 正在创建应用程序图标..."

# 使用 macOS 内置的终端图标作为占位符
ICON_PATH="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Terminal.icns"
TARGET_ICON_PATH="Nexus CLI Restart.app/Contents/Resources/AppIcon.icns"

# 复制图标
if [ -f "$ICON_PATH" ]; then
    cp "$ICON_PATH" "$TARGET_ICON_PATH"
    echo "✅ 图标创建完成"
else
    echo "⚠️ 无法找到默认图标，将使用系统默认图标"
fi

echo ""
echo "💡 提示: 如需自定义图标，请替换文件:"
echo "   $TARGET_ICON_PATH"
echo ""
echo "📋 图标要求:"
echo "   - 格式: .icns"
echo "   - 尺寸: 512x512 像素"
echo "   - 可以使用在线工具转换 PNG 到 ICNS" 