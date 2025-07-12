# 定时重启功能使用说明

## 功能概述

在 Nexus CLI 的批量启动功能中，新增了定时重启主进程的功能。无需使用shell脚本，直接在命令行参数中配置即可实现定时重启。

## 使用方法

### 基本命令格式
```bash
~/nexus-cli/clients/cli/target/release/nexus-network batch-file \
  --file ~/Desktop/nodes.txt \
  --max-concurrent 80 \
  --restart-interval-minutes 1440 \
  --restart-grace-period 30
```

### 新增参数说明

#### `--restart-interval-minutes`
- **类型**: 整数
- **默认值**: 0 (不重启)
- **说明**: 定时重启间隔，单位为分钟
- **示例**: 
  - `--restart-interval-minutes 1440` - 每24小时重启一次（1440分钟）
  - `--restart-interval-minutes 360` - 每6小时重启一次（360分钟）
  - `--restart-interval-minutes 60` - 每1小时重启一次（60分钟）
  - `--restart-interval-minutes 30` - 每30分钟重启一次
  - `--restart-interval-minutes 0` - 不重启（默认行为）

#### `--restart-grace-period`
- **类型**: 整数
- **默认值**: 30
- **说明**: 重启前优雅关闭等待时间，单位为秒
- **示例**: 
  - `--restart-grace-period 60` - 重启前等待60秒
  - `--restart-grace-period 10` - 重启前等待10秒

### 使用示例

#### 1. 每24小时重启一次
```bash
~/nexus-cli/clients/cli/target/release/nexus-network batch-file \
  --file ~/Desktop/nodes.txt \
  --max-concurrent 80 \
  --restart-interval-minutes 1440
```

#### 2. 每6小时重启一次，重启前等待60秒
```bash
~/nexus-cli/clients/cli/target/release/nexus-network batch-file \
  --file ~/Desktop/nodes.txt \
  --max-concurrent 80 \
  --restart-interval-minutes 360 \
  --restart-grace-period 60
```

#### 3. 不重启（原有行为）
```bash
~/nexus-cli/clients/cli/target/release/nexus-network batch-file \
  --file ~/Desktop/nodes.txt \
  --max-concurrent 80
```

## 功能特性

### 🔄 自动重启循环
- 程序会按照设定的时间间隔自动重启
- 每次重启都会记录运行统计信息
- 支持无限循环重启，直到手动停止

### ⏰ 精确计时
- 使用系统时间进行精确计时
- 重启时间基于程序启动时间计算
- 不受节点运行状态影响

### 🛡️ 优雅关闭
- 重启前会发送优雅关闭信号给所有节点
- 等待节点完成当前任务后再关闭
- 可配置优雅关闭等待时间

### 📊 运行统计
- 记录每次运行的时长
- 显示运行次数和状态
- 提供详细的运行日志

## 运行日志示例

```
🔄 启用定时重启功能
⏰ 重启间隔: 1440 分钟
⏳ 优雅关闭等待时间: 30 秒
═══════════════════════════════════════

🚀 第 1 次启动 - 开始时间: 2025-01-11 09:00:00
═══════════════════════════════════════
🚀 Starting batch processing with restart signal support
📊 Total nodes: 80
🔄 Max concurrent: 80
⏱️  Start delay: 10s
🌍 Environment: Production
🧠 Memory-based auto-scaling enabled
═══════════════════════════════════════

... (运行过程中) ...

⏰ 定时重启时间到！准备重启...

🔄 收到重启信号，开始优雅关闭...
✅ 优雅关闭完成，准备重启

📊 第 1 次运行统计:
   ⏱️  运行时长: 24 小时 0 分钟 0 秒
✅ 第 1 次运行正常完成

🔄 准备第 2 次重启...
⏳ 等待 30 秒后开始下一次运行...
═══════════════════════════════════════

🚀 第 2 次启动 - 开始时间: 2025-01-12 09:00:30
...
```

## 技术实现

### 核心组件
- `start_batch_from_file_with_restart`: 主重启循环函数
- `start_batch_with_restart_signal`: 带重启信号的批量处理函数
- `broadcast::channel`: 用于重启信号通信
- `tokio::time::sleep`: 定时器实现

### 重启流程
1. **启动阶段**: 创建重启信号通道和定时器
2. **运行阶段**: 正常批量处理，同时监听重启信号
3. **重启触发**: 定时器到期，发送重启信号
4. **优雅关闭**: 停止节点管理器，等待节点关闭
5. **重启准备**: 等待配置的优雅关闭时间
6. **循环继续**: 开始下一次运行

### 信号处理
- **Ctrl+C**: 立即停止所有节点并退出程序
- **重启信号**: 优雅关闭后重新启动
- **节点完成**: 所有节点处理完毕后退出

## 优势

### 🚀 无需外部脚本
- 功能完全集成在CLI中
- 无需编写复杂的shell脚本
- 跨平台兼容性好

### 🔧 配置灵活
- 可配置重启间隔和优雅关闭时间
- 支持0间隔（不重启）模式
- 保持原有功能的完整性

### 📈 监控友好
- 详细的运行统计信息
- 清晰的日志输出
- 便于监控和调试

### 🛡️ 稳定可靠
- 优雅关闭机制
- 错误处理和恢复
- 内存监控集成

## 注意事项

1. **重启间隔**: 建议设置合理的重启间隔，避免过于频繁
2. **优雅关闭时间**: 根据节点数量调整，确保有足够时间关闭
3. **日志管理**: 长时间运行会产生大量日志，注意磁盘空间
4. **监控**: 建议配合外部监控工具使用
5. **资源使用**: 重启过程中会短暂增加系统负载

## 故障排除

### 重启不生效
- 检查 `--restart-interval-minutes` 参数是否正确设置
- 确认参数值大于0

### 优雅关闭时间过长
- 调整 `--restart-grace-period` 参数
- 检查节点关闭是否正常

### 程序意外退出
- 检查系统资源是否充足
- 查看错误日志定位问题
- 确认节点列表文件格式正确 