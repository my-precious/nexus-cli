#!/bin/bash

# Nexus CLI 定时重启功能使用示例
# 这些示例展示了如何使用新的定时重启功能

echo "🚀 Nexus CLI 定时重启功能使用示例"
echo "═══════════════════════════════════════"

# 示例1: 每24小时重启一次（推荐用于生产环境）
echo "📋 示例1: 每24小时重启一次"
echo "命令:"
echo "~/nexus-cli/clients/cli/target/release/nexus-network batch-file \\"
echo "  --file ~/Desktop/nodes.txt \\"
echo "  --max-concurrent 80 \\"
echo "  --restart-interval-minutes 1440"
echo ""

# 示例2: 每6小时重启一次（适合测试环境）
echo "📋 示例2: 每6小时重启一次"
echo "命令:"
echo "~/nexus-cli/clients/cli/target/release/nexus-network batch-file \\"
echo "  --file ~/Desktop/nodes.txt \\"
echo "  --max-concurrent 80 \\"
echo "  --restart-interval-minutes 360 \\"
echo "  --restart-grace-period 60"
echo ""

# 示例3: 每12小时重启一次，重启前等待2分钟
echo "📋 示例3: 每12小时重启一次，重启前等待2分钟"
echo "命令:"
echo "~/nexus-cli/clients/cli/target/release/nexus-network batch-file \\"
echo "  --file ~/Desktop/nodes.txt \\"
echo "  --max-concurrent 80 \\"
echo "  --restart-interval-minutes 720 \\"
echo "  --restart-grace-period 120"
echo ""

# 示例4: 不重启（原有行为）
echo "📋 示例4: 不重启（原有行为）"
echo "命令:"
echo "~/nexus-cli/clients/cli/target/release/nexus-network batch-file \\"
echo "  --file ~/Desktop/nodes.txt \\"
echo "  --max-concurrent 80"
echo ""

# 示例5: 快速测试（每1小时重启一次）
echo "📋 示例5: 快速测试（每1小时重启一次）"
echo "命令:"
echo "~/nexus-cli/clients/cli/target/release/nexus-network batch-file \\"
echo "  --file ~/Desktop/nodes.txt \\"
echo "  --max-concurrent 10 \\"
echo "  --restart-interval-minutes 60 \\"
echo "  --restart-grace-period 10"
echo ""

echo "═══════════════════════════════════════"
echo "💡 使用提示:"
echo "  - 生产环境建议使用24小时重启间隔"
echo "  - 测试环境可以使用较短的重启间隔"
echo "  - 优雅关闭时间根据节点数量调整"
echo "  - 使用 Ctrl+C 可以立即停止程序"
echo "  - 重启间隔为0时等同于不重启"
echo ""
echo "📚 更多信息请查看: clients/cli/docs/auto_restart_feature.md" 