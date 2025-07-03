# Nexus CLI 批量配置指南 (方法2实现)

## 概述

本指南介绍如何使用 `startup_template.sh` 脚本实现 Nexus CLI 的批量配置和多 Node ID 管理。这是推荐的批量配置方法，可以轻松管理多个 Node ID 实例。

## 🚀 快速开始

### 1. 配置 Node ID

编辑 `startup_template.sh` 文件，修改 `NODE_IDS` 数组：

```bash
# 编辑配置文件
nano startup_template.sh

# 找到 NODE_IDS 数组，替换为您的实际 Node ID
NODE_IDS=(
    "5644400"    # 实例 1
    "5636920"    # 实例 2
    "5616391"    # 实例 3
    "5644463"    # 实例 4
    "5587340"    # 实例 5
    # 添加更多 Node ID...
)
```

### 2. 批量启动

```bash
# 启动所有配置的实例
./startup_template.sh start

# 查看启动状态
./startup_template.sh status

# 实时监控
./nexus_monitor.sh
```

### 3. 管理实例

```bash
# 停止所有实例
./startup_template.sh stop

# 重启所有实例
./startup_template.sh restart

# 查看配置信息
./startup_template.sh config
```

## 📋 详细配置

### Node ID 配置

在 `startup_template.sh` 中可以配置的参数：

```bash
# Node ID 列表
NODE_IDS=(
    "5644400"
    "5636920"
    # 添加更多...
)

# 其他配置参数
MAX_THREADS=4           # 每个实例的最大线程数
HEADLESS=true          # 是否使用无头模式
ENVIRONMENT="testnet"   # 环境设置
START_DELAY=2          # 实例启动间隔（秒）
```

### 交互式配置

```bash
# 交互式添加 Node ID
./startup_template.sh interactive
```

## 🛠️ 单实例管理

除了批量管理，您也可以使用 `nexus_multi_runner.sh` 管理单个实例：

```bash
# 启动单个实例（新的参数格式）
./nexus_multi_runner.sh start 1 --node-id 5644400 --max-threads 4

# 启动实例（仅指定 Node ID）
./nexus_multi_runner.sh start 2 --node-id 5636920

# 重启实例并更改 Node ID
./nexus_multi_runner.sh restart 1 --node-id 5616391 --max-threads 2

# 查看所有实例状态
./nexus_multi_runner.sh status

# 查看实例日志
./nexus_multi_runner.sh logs 1 50
```

## 📊 监控和管理

### 实时监控

```bash
# 启动监控界面
./nexus_monitor.sh

# 或使用内置监控
./nexus_multi_runner.sh monitor
```

### 日志管理

```bash
# 查看特定实例日志
./nexus_multi_runner.sh logs <实例ID> [行数]

# 示例：查看实例1的最近100行日志
./nexus_multi_runner.sh logs 1 100
```

### 进程清理

```bash
# 清理死进程和PID文件
./nexus_multi_runner.sh clean
```

## 🔧 高级功能

### 自定义启动参数

在 `startup_template.sh` 中，您可以为不同实例设置不同的参数：

```bash
# 修改 start_all_instances 函数
start_all_instances() {
    # ... 现有代码 ...
    
    for i in "${!NODE_IDS[@]}"; do
        local instance_id=$((i + 1))
        local node_id="${NODE_IDS[$i]}"
        
        # 自定义参数示例
        local custom_threads=$MAX_THREADS
        if [[ $instance_id -eq 1 ]]; then
            custom_threads=8  # 实例1使用8个线程
        fi
        
        # 构建启动命令
        local start_cmd="$MULTI_RUNNER start $instance_id"
        start_cmd="$start_cmd --node-id $node_id"
        start_cmd="$start_cmd --max-threads $custom_threads"
        
        # ... 其他代码 ...
    done
}
```

### 批量操作脚本

创建自定义批量操作：

```bash
#!/bin/bash
# 自定义批量启动脚本

# 启动前5个实例
for i in {1..5}; do
    ./nexus_multi_runner.sh start $i --node-id "$(sed -n "${i}p" node_ids_example.txt)" --max-threads 4
    sleep 2
done
```

## 📁 文件结构

```
nexus-cli/
├── nexus_multi_runner.sh      # 主管理脚本
├── startup_template.sh        # 批量配置模板（方法2）
├── nexus_monitor.sh          # 监控脚本
├── node_ids_example.txt      # Node ID 示例文件
├── BATCH_SETUP_GUIDE.md      # 本指南
└── logs/                     # 日志目录
    ├── nexus_1.log
    ├── nexus_2.log
    └── ...
```

## 🔍 故障排除

### 常见问题

1. **Node ID 格式错误**
   ```bash
   # 确保 Node ID 是纯数字
   "5644400"  # ✅ 正确
   "node_123" # ❌ 错误
   ```

2. **实例启动失败**
   ```bash
   # 检查日志
   ./nexus_multi_runner.sh logs <实例ID>
   
   # 清理死进程
   ./nexus_multi_runner.sh clean
   ```

3. **配置文件问题**
   ```bash
   # 检查配置
   ./startup_template.sh config
   
   # 验证脚本权限
   chmod +x startup_template.sh
   chmod +x nexus_multi_runner.sh
   ```

### 调试模式

```bash
# 启用调试输出
bash -x ./startup_template.sh start
```

## 📝 最佳实践

1. **测试单个实例**：在批量启动前，先测试单个实例
2. **监控资源**：使用监控脚本观察系统资源使用情况
3. **定期清理**：定期运行清理命令移除死进程
4. **备份配置**：备份您的 Node ID 配置
5. **渐进启动**：设置适当的启动间隔，避免系统过载

## 🎯 使用场景

### 场景1：首次批量部署
```bash
# 1. 配置 Node ID
nano startup_template.sh

# 2. 批量启动
./startup_template.sh start

# 3. 监控状态
./nexus_monitor.sh
```

### 场景2：添加新的 Node ID
```bash
# 交互式添加
./startup_template.sh interactive

# 或直接编辑配置
nano startup_template.sh
```

### 场景3：维护和重启
```bash
# 停止所有实例
./startup_template.sh stop

# 清理环境
./nexus_multi_runner.sh clean

# 重新启动
./startup_template.sh start
```

## 🔗 相关文档

- [MULTI_RUNNER_README.md](./MULTI_RUNNER_README.md) - 完整功能文档
- [node_ids_example.txt](./node_ids_example.txt) - Node ID 示例

---

**注意**：请确保您的 Node ID 是有效的，并且已经在 Nexus 网络中注册。使用无效的 Node ID 可能导致挖矿失败。







nexus-network start --node-id 6573055 
nexus-network start --node-id 6587645
nexus-network start --node-id 6804604
nexus-network start --node-id 7126222  
nexus-network start --node-id 7215856 
