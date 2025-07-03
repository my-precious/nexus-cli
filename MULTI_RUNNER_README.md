# Nexus CLI 多开管理工具

这是一个为 Nexus 挖矿项目设计的多实例管理和监控系统，允许您同时运行多个 Nexus CLI 实例，并提供实时监控界面。

## 🚀 功能特性

- **多实例管理**: 同时运行多达10个独立的 Nexus CLI 实例
- **实时监控**: 美观的终端界面显示实例状态、CPU/内存使用情况
- **日志管理**: 每个实例独立的日志文件和实时日志查看
- **进程管理**: 安全的启动、停止、重启实例功能
- **性能统计**: 系统资源使用情况和性能报告
- **交互式界面**: 支持键盘控制的监控界面
- **批量操作**: 一键启动/停止多个实例

## 📋 系统要求

- **操作系统**: macOS 或 Linux
- **Rust**: 1.85+ (用于编译 Nexus CLI)
- **依赖工具**: `ps`, `kill`, `tail`, `grep`, `awk`, `sed`
- **终端**: 支持 ANSI 颜色和 Unicode 字符的终端

## 🛠️ 安装步骤

### 1. 自动安装 (推荐)

```bash
# 克隆项目 (如果还没有)
git clone <nexus-cli-repo>
cd nexus-cli

# 运行安装脚本
chmod +x setup.sh
./setup.sh install
```

### 2. 手动安装

```bash
# 编译 Nexus CLI
cd clients/cli
cargo build --release
cd ../..

# 设置脚本权限
chmod +x nexus_multi_runner.sh
chmod +x nexus_monitor.sh
chmod +x setup.sh

# 创建必要目录
mkdir -p ~/.nexus/{logs,pids,instances,backups}
```

## 📖 使用指南

### 基本命令

#### 多实例管理 (`nexus_multi_runner.sh`)

```bash
# 启动单个实例
./nexus_multi_runner.sh start 1 2        # 启动实例1，使用2个线程
./nexus_multi_runner.sh start 2 4 123456 # 启动实例2，使用4个线程，节点ID为123456

# 批量启动
./nexus_multi_runner.sh batch-start 5 2  # 启动5个实例，每个使用2个线程

# 查看状态
./nexus_multi_runner.sh status           # 显示所有实例状态

# 停止实例
./nexus_multi_runner.sh stop 1           # 停止实例1
./nexus_multi_runner.sh batch-stop       # 停止所有实例

# 重启实例
./nexus_multi_runner.sh restart 1 2      # 重启实例1，使用2个线程

# 查看日志
./nexus_multi_runner.sh logs 1 50        # 显示实例1的最近50行日志

# 清理死进程
./nexus_multi_runner.sh clean            # 清理死进程和PID文件
```

#### 实时监控 (`nexus_monitor.sh`)

```bash
# 交互式监控 (默认)
./nexus_monitor.sh

# 显示一次状态
./nexus_monitor.sh -s

# 查看特定实例日志
./nexus_monitor.sh -l 1

# 生成性能报告
./nexus_monitor.sh -r
```

### 交互式监控界面

启动监控界面后，您可以使用以下快捷键：

- **↑/↓ 箭头键**: 选择实例
- **L**: 切换日志/状态视图
- **R**: 强制刷新
- **Q**: 退出监控

### 快捷命令 (如果已添加到PATH)

```bash
nexus-multi status                # 查看状态
nexus-multi batch-start 5 2       # 批量启动
nexus-monitor                     # 启动监控界面
```

## 🎯 使用场景

### 场景1: 快速开始挖矿

```bash
# 1. 安装环境
./setup.sh install

# 2. 启动5个实例，每个使用2个线程
./nexus_multi_runner.sh batch-start 5 2

# 3. 查看实时监控
./nexus_monitor.sh
```

### 场景2: 已注册用户多开

```bash
# 使用已注册的节点ID启动实例
./nexus_multi_runner.sh start 1 4 123456
./nexus_multi_runner.sh start 2 4 123457
./nexus_multi_runner.sh start 3 4 123458

# 查看状态
./nexus_multi_runner.sh status
```

### 场景3: 性能优化

```bash
# 根据CPU核心数调整线程
# 例如：8核CPU，启动4个实例，每个2线程
./nexus_multi_runner.sh batch-start 4 2

# 监控性能
./nexus_monitor.sh

# 生成性能报告
./nexus_monitor.sh -r
```

## 📁 文件结构

```
nexus-cli/
├── nexus_multi_runner.sh     # 主管理脚本
├── nexus_monitor.sh          # 监控界面脚本
├── setup.sh                  # 安装配置脚本
├── MULTI_RUNNER_README.md    # 本文档
└── clients/cli/
    └── target/release/
        └── nexus-network     # 编译后的可执行文件

~/.nexus/                     # 配置目录
├── logs/                     # 日志文件
│   ├── nexus_1.log
│   ├── nexus_2.log
│   └── ...
├── pids/                     # 进程ID文件
│   ├── nexus_1.pid
│   ├── nexus_2.pid
│   └── ...
├── instances/                # 实例配置
├── backups/                  # 备份文件
├── example_config.json       # 示例配置
└── startup_template.sh       # 启动模板
```

## ⚙️ 配置说明

### 环境变量

- `NEXUS_ENVIRONMENT`: 设置运行环境 (默认: production)
- `MAX_INSTANCES`: 最大实例数 (默认: 10)
- `REFRESH_INTERVAL`: 监控刷新间隔 (默认: 2秒)

### 配置文件

每个实例都有独立的配置目录 `~/.nexus_<实例ID>/`，包含：

```json
{
  "environment": "production",
  "user_id": "your-user-id",
  "wallet_address": "0x...",
  "node_id": "123456"
}
```

## 🔧 高级功能

### 自定义启动脚本

编辑 `~/.nexus/startup_template.sh` 来创建自定义启动配置：

```bash
#!/bin/bash
# 自定义启动配置

INSTANCE_COUNT=8
THREADS_PER_INSTANCE=2

# 节点ID列表
NODE_IDS=(
    "123456"
    "123457"
    "123458"
)

# 批量启动
./nexus_multi_runner.sh batch-start "$INSTANCE_COUNT" "$THREADS_PER_INSTANCE"
```

### 性能调优建议

1. **CPU线程分配**:
   - 总线程数不要超过CPU核心数
   - 建议：实例数 × 线程数 ≤ CPU核心数

2. **内存使用**:
   - 每个实例大约使用 100-500MB 内存
   - 确保有足够的可用内存

3. **网络优化**:
   - 避免同时启动过多实例造成网络拥塞
   - 可以分批启动，间隔1-2秒

### 日志管理

```bash
# 查看所有实例日志大小
du -sh ~/.nexus/logs/*

# 清理旧日志 (保留最近1000行)
for log in ~/.nexus/logs/*.log; do
    tail -n 1000 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
done

# 备份日志
tar -czf ~/.nexus/backups/logs_$(date +%Y%m%d).tar.gz ~/.nexus/logs/
```

## 🐛 故障排除

### 常见问题

1. **编译失败**
   ```bash
   # 更新 Rust
   rustup update
   
   # 清理并重新编译
   cd clients/cli
   cargo clean
   cargo build --release
   ```

2. **实例启动失败**
   ```bash
   # 检查日志
   ./nexus_multi_runner.sh logs 1
   
   # 清理死进程
   ./nexus_multi_runner.sh clean
   
   # 重新启动
   ./nexus_multi_runner.sh restart 1
   ```

3. **监控界面显示异常**
   ```bash
   # 检查终端支持
   echo $TERM
   
   # 使用简单模式
   ./nexus_monitor.sh -s
   ```

4. **权限问题**
   ```bash
   # 重新设置权限
   chmod +x *.sh
   
   # 检查目录权限
   ls -la ~/.nexus/
   ```

### 调试模式

```bash
# 启用调试输出
export DEBUG=1
./nexus_multi_runner.sh status

# 查看详细进程信息
ps aux | grep nexus-network

# 检查端口使用
lsof -i :8080-8090
```

## 📊 监控界面说明

### 状态显示

- 🟢 **运行**: 实例正常运行
- 🔴 **停止**: 实例已停止
- 💀 **死亡**: 进程异常退出

### 性能指标

- **CPU%**: 实例CPU使用率
- **MEM%**: 实例内存使用率
- **运行时间**: 实例运行时长
- **总计**: 所有实例的资源使用总和

### 日志颜色

- 🔴 **红色**: 错误信息
- 🟡 **黄色**: 警告信息
- 🟢 **绿色**: 成功信息
- ⚪ **白色**: 普通信息

## 🔄 更新和维护

### 更新脚本

```bash
# 备份当前配置
cp -r ~/.nexus ~/.nexus.backup

# 更新代码
git pull

# 重新安装
./setup.sh install
```

### 定期维护

```bash
# 每周清理日志
./nexus_monitor.sh -r  # 生成报告
# 手动清理大日志文件

# 每月备份配置
tar -czf ~/.nexus/backups/config_$(date +%Y%m).tar.gz ~/.nexus/instances/
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进这个工具！

### 开发环境

```bash
# 克隆项目
git clone <repo>
cd nexus-cli

# 安装开发依赖
./setup.sh install

# 运行测试
./setup.sh test
```

## 📄 许可证

本项目遵循与 Nexus CLI 相同的许可证。

## ⚠️ 免责声明

- 本工具仅用于学习和研究目的
- 使用前请确保遵守相关法律法规
- 作者不对使用本工具造成的任何损失负责
- 请合理使用系统资源，避免影响其他应用

## 📞 支持

如果您遇到问题或有建议，请：

1. 查看本文档的故障排除部分
2. 检查 GitHub Issues
3. 提交新的 Issue 描述问题

---

**祝您挖矿愉快！** 🚀⛏️