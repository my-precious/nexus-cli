# Nexus CLI 自动重启监控使用指南

## 概述

自动重启监控功能可以检测 Nexus CLI 实例是否卡住（连续5分钟输出 "Performance: 0"），并自动重启卡住的实例，确保服务的持续稳定运行。

## 功能特性

- 🔍 **智能检测**: 监控日志中的 "Performance: 0" 输出
- ⏰ **时间阈值**: 连续5分钟检测到问题才触发重启
- 🔄 **自动重启**: 自动重启卡住的实例
- 📊 **状态跟踪**: 记录每个实例的监控状态
- 📝 **详细日志**: 完整的监控和重启日志
- 🛡️ **安全机制**: 防止频繁重启的保护措施

## 快速开始

### 1. 使用批量管理脚本（推荐）

```bash
# 启动所有实例（自动开启监控）
./startup_template.sh start

# 查看监控状态
./startup_template.sh monitor status

# 停止所有实例（自动停止监控）
./startup_template.sh stop
```

### 2. 手动管理监控服务

```bash
# 启动监控服务
./startup_template.sh monitor start

# 停止监控服务
./startup_template.sh monitor stop

# 查看监控状态
./startup_template.sh monitor status

# 查看监控日志
./startup_template.sh monitor logs
```

### 3. 直接使用监控脚本

```bash
# 启动监控
./auto_restart_monitor.sh start

# 查看状态
./auto_restart_monitor.sh status

# 查看日志
./auto_restart_monitor.sh logs

# 停止监控
./auto_restart_monitor.sh stop
```

## 监控配置

### 默认配置

- **监控间隔**: 30秒检查一次
- **超时时间**: 连续5分钟（300秒）
- **最大重启次数**: 每小时最多3次
- **重启冷却时间**: 重启后等待10分钟再次监控

### 自定义配置

编辑 `auto_restart_monitor.sh` 文件顶部的配置区域：

```bash
# 监控配置
CHECK_INTERVAL=30          # 检查间隔（秒）
PERFORMANCE_TIMEOUT=300    # 超时时间（秒）
MAX_RESTART_ATTEMPTS=3     # 最大重启尝试次数
RESTART_COOLDOWN=600       # 重启冷却时间（秒）
```

## 监控工作原理

### 检测逻辑

1. **日志监控**: 定期检查每个实例的日志文件
2. **性能检测**: 查找最近的 "Performance" 输出
3. **时间判断**: 如果连续5分钟都是 "Performance: 0"，判定为卡住
4. **自动重启**: 停止卡住的实例并重新启动
5. **状态记录**: 更新实例状态和重启历史

### 状态文件

监控服务会创建以下文件：

- `~/.nexus_monitor/monitor.pid` - 监控服务进程ID
- `~/.nexus_monitor/monitor.log` - 监控日志
- `~/.nexus_monitor/instance_*.state` - 实例状态文件

## 使用场景

### 场景1: 长期运行的挖矿实例

```bash
# 启动所有实例并开启监控
./startup_template.sh start

# 定期检查状态（可选）
./startup_template.sh monitor status
```

### 场景2: 测试环境

```bash
# 只启动实例，不开启监控
./nexus_multi_runner.sh batch-start 3 --max-threads 4

# 手动启动监控
./startup_template.sh monitor start
```

### 场景3: 故障排除

```bash
# 查看监控日志
./startup_template.sh monitor logs

# 查看特定实例日志
./nexus_multi_runner.sh logs 1

# 重启监控服务
./startup_template.sh monitor stop
./startup_template.sh monitor start
```

## 监控命令详解

### startup_template.sh monitor 命令

| 命令 | 说明 |
|------|------|
| `monitor start` | 启动自动重启监控服务 |
| `monitor stop` | 停止自动重启监控服务 |
| `monitor status` | 查看监控服务和实例状态 |
| `monitor logs` | 查看监控日志（最近100行） |

### auto_restart_monitor.sh 命令

| 命令 | 说明 |
|------|------|
| `start` | 启动监控服务 |
| `stop` | 停止监控服务 |
| `status` | 显示详细状态信息 |
| `logs [行数]` | 查看监控日志 |
| `clean` | 清理旧日志文件 |
| `help` | 显示帮助信息 |

## 故障排除

### 常见问题

#### 1. 监控服务启动失败

```bash
# 检查脚本权限
ls -la auto_restart_monitor.sh

# 设置执行权限
chmod +x auto_restart_monitor.sh

# 检查依赖脚本
ls -la nexus_multi_runner.sh
```

#### 2. 监控服务无法检测到实例

```bash
# 确认实例正在运行
./nexus_multi_runner.sh status

# 检查日志文件路径
ls ~/.nexus_*/nexus.log

# 手动检查日志内容
tail ~/.nexus_1/nexus.log
```

#### 3. 重启过于频繁

```bash
# 查看监控日志
./auto_restart_monitor.sh logs 50

# 调整配置参数
# 编辑 auto_restart_monitor.sh，增加 RESTART_COOLDOWN 值
```

### 日志分析

#### 监控日志格式

```
[2024-01-15 10:30:00] [INFO] 开始监控实例 1
[2024-01-15 10:30:30] [WARN] 实例 1 检测到 Performance: 0 (1/10)
[2024-01-15 10:35:00] [ERROR] 实例 1 连续5分钟 Performance: 0，准备重启
[2024-01-15 10:35:05] [INFO] 实例 1 重启成功
```

#### 状态文件内容

```bash
# 查看实例状态
cat ~/.nexus_monitor/instance_1.state
```

## 最佳实践

### 1. 监控配置建议

- **生产环境**: 使用默认配置，确保稳定性
- **测试环境**: 可以缩短检查间隔，快速发现问题
- **资源受限**: 增加检查间隔，减少系统负载

### 2. 日志管理

```bash
# 定期清理旧日志
./auto_restart_monitor.sh clean

# 或者设置定时任务
echo "0 2 * * * cd /path/to/nexus-cli && ./auto_restart_monitor.sh clean" | crontab -
```

### 3. 监控告警

可以结合系统监控工具，监控以下指标：

- 监控服务进程状态
- 重启频率
- 实例运行时间
- 日志文件大小

### 4. 备份和恢复

```bash
# 备份配置
cp auto_restart_monitor.sh auto_restart_monitor.sh.bak
cp startup_template.sh startup_template.sh.bak

# 备份状态文件
tar -czf nexus_monitor_backup.tar.gz ~/.nexus_monitor/
```

## 高级功能

### 1. 自定义检测条件

编辑 `auto_restart_monitor.sh` 中的 `check_performance_zero` 函数，可以自定义检测逻辑。

### 2. 集成外部通知

在重启函数中添加通知逻辑：

```bash
# 发送邮件通知
echo "实例 $instance_id 已重启" | mail -s "Nexus 实例重启通知" admin@example.com

# 发送 Slack 通知
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"实例 '$instance_id' 已重启"}' \
  YOUR_SLACK_WEBHOOK_URL
```

### 3. 性能优化

- 使用 `tail -f` 实时监控日志
- 实现增量日志分析
- 添加内存使用监控

## 总结

自动重启监控功能为 Nexus CLI 提供了可靠的故障恢复机制。通过合理配置和使用，可以显著提高服务的可用性和稳定性。

如有问题或建议，请查看日志文件或联系技术支持。