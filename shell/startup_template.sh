#!/bin/bash

# Nexus CLI 批量启动模板脚本
# 用于配置和启动多个 node_id 实例

# =============================================================================
# 配置区域 - 请根据需要修改以下配置
# =============================================================================

# Node ID 配置文件路径
NODE_IDS_FILE="$HOME/.nexus/node_ids.conf"

# 从配置文件加载 node_id 列表
load_node_ids() {
    local node_ids=()
    
    if [[ ! -f "$NODE_IDS_FILE" ]]; then
        echo "错误: 找不到 Node ID 配置文件: $NODE_IDS_FILE" >&2
        echo "请创建配置文件或检查文件路径" >&2
        exit 1
    fi
    
    # 读取配置文件，忽略注释行和空行
    while IFS= read -r line; do
        # 跳过空行和注释行
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            # 去除前后空格
            line=$(echo "$line" | xargs)
            if [[ -n "$line" ]]; then
                node_ids+=("$line")
            fi
        fi
    done < "$NODE_IDS_FILE"
    
    echo "${node_ids[@]}"
}

# 加载 node_id 列表
NODE_IDS=($(load_node_ids))

# 其他配置参数
MAX_THREADS=2          # 每个实例的最大线程数
HEADLESS=true          # 是否使用无头模式
ENVIRONMENT="testnet"   # 环境设置
START_DELAY=4          # 实例启动间隔（秒）

# 脚本路径配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MULTI_RUNNER="$SCRIPT_DIR/nexus_multi_runner.sh"
AUTO_RESTART_MONITOR="$SCRIPT_DIR/auto_restart_monitor.sh"

# =============================================================================
# 颜色定义
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# 辅助函数
# =============================================================================

# 打印带颜色的消息
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# 打印标题
print_title() {
    echo
    print_message $CYAN "=== $1 ==="
    echo
}

# 检查依赖
check_dependencies() {
    if [[ ! -f "$MULTI_RUNNER" ]]; then
        print_message $RED "错误: 找不到 nexus_multi_runner.sh 脚本"
        print_message $YELLOW "请确保 nexus_multi_runner.sh 在同一目录下"
        exit 1
    fi
    
    if [[ ! -x "$MULTI_RUNNER" ]]; then
        print_message $YELLOW "设置 nexus_multi_runner.sh 执行权限..."
        chmod +x "$MULTI_RUNNER"
    fi
    
    if [[ ! -f "$AUTO_RESTART_MONITOR" ]]; then
        print_message $YELLOW "警告: 找不到 auto_restart_monitor.sh 脚本"
        print_message $YELLOW "自动重启监控功能将不可用"
    elif [[ ! -x "$AUTO_RESTART_MONITOR" ]]; then
        print_message $YELLOW "设置 auto_restart_monitor.sh 执行权限..."
        chmod +x "$AUTO_RESTART_MONITOR"
    fi
}

# 验证 node_id 格式
validate_node_ids() {
    local invalid_ids=()
    
    for node_id in "${NODE_IDS[@]}"; do
        if [[ ! "$node_id" =~ ^[0-9]+$ ]]; then
            invalid_ids+=("$node_id")
        fi
    done
    
    if [[ ${#invalid_ids[@]} -gt 0 ]]; then
        print_message $RED "错误: 发现无效的 node_id 格式:"
        for invalid_id in "${invalid_ids[@]}"; do
            print_message $RED "  - $invalid_id"
        done
        print_message $YELLOW "node_id 必须是纯数字格式"
        exit 1
    fi
}

# =============================================================================
# 主要功能函数
# =============================================================================

# 启动自动重启监控
start_auto_monitor() {
    if [[ -f "$AUTO_RESTART_MONITOR" ]]; then
        print_message $CYAN "启动自动重启监控服务..."
        rm -rf ./monitor_state/*.json
        if "$AUTO_RESTART_MONITOR" start; then
            print_message $GREEN "✓ 自动重启监控服务启动成功"
        else
            print_message $YELLOW "⚠ 自动重启监控服务启动失败，将继续运行实例"
        fi
    else
        print_message $YELLOW "⚠ 自动重启监控脚本不存在，跳过监控启动"
    fi
}

# 停止自动重启监控
stop_auto_monitor() {
    if [[ -f "$AUTO_RESTART_MONITOR" ]]; then
        print_message $CYAN "停止自动重启监控服务..."
        if "$AUTO_RESTART_MONITOR" stop; then
            print_message $GREEN "✓ 自动重启监控服务停止成功"
        else
            print_message $YELLOW "⚠ 自动重启监控服务停止失败"
        fi
    fi
}

# 启动所有实例
start_all_instances() {
    print_title "批量启动 Nexus CLI 实例"
    
    print_message $BLUE "配置信息:"
    echo "  - 实例数量: ${#NODE_IDS[@]}"
    echo "  - 最大线程: $MAX_THREADS"
    echo "  - 无头模式: $HEADLESS"
    echo "  - 环境设置: $ENVIRONMENT"
    echo "  - 启动间隔: ${START_DELAY}秒"
    echo
    
    rm -rf ~/.nexus/logs/*.log
    
    local success_count=0
    local failed_count=0
    
    for i in "${!NODE_IDS[@]}"; do
        local instance_id=$((i + 1))
        local node_id="${NODE_IDS[$i]}"
        
        print_message $CYAN "启动实例 $instance_id (Node ID: $node_id)..."
        
        # 构建启动命令
        local start_cmd="$MULTI_RUNNER start $instance_id"
        
        # 添加 node_id 参数
        start_cmd="$start_cmd --node-id $node_id"
        
        # 添加其他参数
        if [[ "$HEADLESS" == "true" ]]; then
            start_cmd="$start_cmd --headless"
        fi
        
        if [[ -n "$MAX_THREADS" && "$MAX_THREADS" -gt 0 ]]; then
            start_cmd="$start_cmd --max-threads $MAX_THREADS"
        fi
        
        # 执行启动命令
        if eval "$start_cmd"; then
            print_message $GREEN "✓ 实例 $instance_id 启动成功"
            ((success_count++))
        else
            print_message $RED "✗ 实例 $instance_id 启动失败"
            ((failed_count++))
        fi
        
        # 启动间隔
        if [[ $i -lt $((${#NODE_IDS[@]} - 1)) ]]; then
            print_message $YELLOW "等待 ${START_DELAY} 秒后启动下一个实例..."
            sleep $START_DELAY
        fi
    done
    
    echo
    print_message $BLUE "批量启动完成:"
    print_message $GREEN "  - 成功: $success_count 个实例"
    if [[ $failed_count -gt 0 ]]; then
        print_message $RED "  - 失败: $failed_count 个实例"
    fi
    
    # 启动自动重启监控
    if [[ $success_count -gt 0 ]]; then
        echo
        start_auto_monitor
    fi
}

# 停止所有实例
stop_all_instances() {
    print_title "批量停止 Nexus CLI 实例"
    
    # 先停止自动重启监控
    stop_auto_monitor
    echo
    
    local success_count=0
    local failed_count=0
    
    for i in "${!NODE_IDS[@]}"; do
        local instance_id=$((i + 1))
        local node_id="${NODE_IDS[$i]}"
        
        print_message $CYAN "停止实例 $instance_id (Node ID: $node_id)..."
        
        if "$MULTI_RUNNER" stop-by-node "$node_id"; then
            print_message $GREEN "✓ 实例 $instance_id 停止成功"
            ((success_count++))
        else
            print_message $RED "✗ 实例 $instance_id 停止失败"
            ((failed_count++))
        fi
    done
    
    echo
    print_message $BLUE "批量停止完成:"
    print_message $GREEN "  - 成功: $success_count 个实例"
    if [[ $failed_count -gt 0 ]]; then
        print_message $RED "  - 失败: $failed_count 个实例"
    fi
}

# 重启所有实例
restart_all_instances() {
    print_title "批量重启 Nexus CLI 实例"
    
    print_message $CYAN "停止所有实例..."
    # 先停止自动重启监控
    stop_auto_monitor
    echo
    
    if "$MULTI_RUNNER" batch-stop; then
        print_message $GREEN "✓ 所有实例停止成功"
    else
        print_message $RED "✗ 停止实例时出现错误"
    fi
    
    echo
    print_message $CYAN "等待 3 秒后重新启动..."
    sleep 3
    
    start_all_instances
}

# 显示所有实例状态
show_all_status() {
    print_title "所有实例状态"
    
    "$MULTI_RUNNER" status
}

# 显示配置信息
show_config() {
    print_title "当前配置信息"
    
    print_message $BLUE "配置文件路径:"
    echo "  $NODE_IDS_FILE"
    
    echo
    print_message $BLUE "Node ID 列表 (共 ${#NODE_IDS[@]} 个):"
    for i in "${!NODE_IDS[@]}"; do
        local instance_id=$((i + 1))
        local node_id="${NODE_IDS[$i]}"
        echo "  实例 $instance_id: $node_id"
    done
    
    echo
    print_message $BLUE "其他配置:"
    echo "  - 最大线程数: $MAX_THREADS"
    echo "  - 无头模式: $HEADLESS"
    echo "  - 环境设置: $ENVIRONMENT"
    echo "  - 启动间隔: ${START_DELAY}秒"
}

# 交互式配置
interactive_config() {
    print_title "交互式配置"
    
    print_message $YELLOW "当前有 ${#NODE_IDS[@]} 个 Node ID 配置"
    echo
    
    read -p "是否要添加新的 Node ID? (y/n): " add_new
    if [[ "$add_new" =~ ^[Yy]$ ]]; then
        local new_node_ids=()
        while true; do
            read -p "请输入新的 Node ID (纯数字，回车结束): " new_node_id
            if [[ -z "$new_node_id" ]]; then
                break
            fi
            
            if [[ "$new_node_id" =~ ^[0-9]+$ ]]; then
                new_node_ids+=("$new_node_id")
                print_message $GREEN "✓ 已添加 Node ID: $new_node_id"
            else
                print_message $RED "✗ 无效格式，Node ID 必须是纯数字"
            fi
        done
        
        # 将新的 Node ID 写入配置文件
        if [[ ${#new_node_ids[@]} -gt 0 ]]; then
            print_message $CYAN "正在更新配置文件..."
            for node_id in "${new_node_ids[@]}"; do
                echo "$node_id" >> "$NODE_IDS_FILE"
            done
            print_message $GREEN "✓ 配置文件已更新"
            
            # 重新加载配置
            NODE_IDS=($(load_node_ids))
            print_message $GREEN "✓ 配置已重新加载，当前共有 ${#NODE_IDS[@]} 个 Node ID"
        fi
    fi
    
    echo
    read -p "最大线程数 (当前: $MAX_THREADS): " new_threads
    if [[ -n "$new_threads" && "$new_threads" =~ ^[0-9]+$ ]]; then
        MAX_THREADS="$new_threads"
    fi
    
    read -p "启动间隔秒数 (当前: $START_DELAY): " new_delay
    if [[ -n "$new_delay" && "$new_delay" =~ ^[0-9]+$ ]]; then
        START_DELAY="$new_delay"
    fi
    
    print_message $GREEN "配置更新完成！"
}

# =============================================================================
# 帮助信息
# =============================================================================

show_help() {
    cat << EOF
${CYAN}Nexus CLI 批量启动模板脚本${NC}

${YELLOW}用法:${NC}
  $0 [命令] [选项]

${YELLOW}命令:${NC}
  start       批量启动所有配置的实例（自动启动监控）
  stop        批量停止所有实例（自动停止监控）
  restart     批量重启所有实例
  status      显示所有实例状态
  config      显示当前配置信息
  edit-config 编辑 Node ID 配置文件
  interactive 交互式配置 Node ID
  monitor     管理自动重启监控服务
  help        显示此帮助信息

${YELLOW}监控命令:${NC}
  monitor start   启动自动重启监控服务
  monitor stop    停止自动重启监控服务
  monitor status  查看监控服务状态
  monitor logs    查看监控日志
  monitor watch   实时监控状态 (自动刷新)

${YELLOW}示例:${NC}
  $0 start              # 启动所有实例并开启监控
  $0 stop               # 停止所有实例
  $0 restart            # 重启所有实例
  $0 status             # 查看状态
  $0 config             # 查看配置
  $0 edit-config        # 编辑配置文件
  $0 monitor status     # 查看监控状态
  $0 monitor watch      # 实时监控状态
  $0 interactive        # 交互式配置

${YELLOW}配置说明:${NC}
  - Node ID 配置存储在外部文件: node_ids.conf
  - 每行一个 Node ID，支持注释（以 # 开头）
  - 可以通过修改其他配置变量来调整启动参数
  - 支持交互式添加新的 Node ID（会自动更新配置文件）
  - 自动重启监控会在检测到连续5分钟'Performance: 0'时重启实例

${YELLOW}注意事项:${NC}
  - Node ID 必须是纯数字格式
  - 确保 nexus_multi_runner.sh 在同一目录下
  - 建议先测试单个实例再批量启动
  - 监控服务会自动管理，也可手动控制

EOF
}

# =============================================================================
# 主程序
# =============================================================================

# 检查依赖
check_dependencies

# 验证 node_id
validate_node_ids

# 主命令处理
case "$1" in
    "start")
        start_all_instances
        ;;
    "stop")
        stop_all_instances
        ;;
    "restart")
        restart_all_instances
        ;;
    "status")
        show_status
        ;;
    "config")
        show_config
        ;;
    "edit-config")
        print_message $CYAN "正在打开配置文件进行编辑..."
        if command -v nano >/dev/null 2>&1; then
            nano "$NODE_IDS_FILE"
        elif command -v vim >/dev/null 2>&1; then
            vim "$NODE_IDS_FILE"
        elif command -v vi >/dev/null 2>&1; then
            vi "$NODE_IDS_FILE"
        else
            print_message $RED "错误: 找不到可用的文本编辑器 (nano, vim, vi)"
            print_message $YELLOW "请手动编辑配置文件: $NODE_IDS_FILE"
        fi
        print_message $GREEN "配置文件编辑完成"
        ;;
    "interactive")
        interactive_config
        ;;
    "monitor")
        case "$2" in
            "start")
                start_auto_monitor
                ;;
            "stop")
                stop_auto_monitor
                ;;
            "status")
                if [[ -f "$AUTO_RESTART_MONITOR" ]]; then
                    "$AUTO_RESTART_MONITOR" status
                else
                    print_message $RED "错误: 找不到自动重启监控脚本"
                fi
                ;;
            "logs")
                if [[ -f "$AUTO_RESTART_MONITOR" ]]; then
                    "$AUTO_RESTART_MONITOR" logs
                else
                    print_message $RED "错误: 找不到自动重启监控脚本"
                fi
                ;;
            "watch")
                if [[ -f "$AUTO_RESTART_MONITOR" ]]; then
                    print_message $GREEN "启动实时监控界面 (按 Ctrl+C 退出)..."
                    echo
                    while true; do
                        clear
                        echo "=== 实时监控状态 ($(date '+%Y-%m-%d %H:%M:%S')) ==="
                        echo
                        "$AUTO_RESTART_MONITOR" status
                        echo
                        echo "按 Ctrl+C 退出实时监控"
                        sleep 3
                    done
                else
                    print_message $RED "错误: 找不到自动重启监控脚本"
                fi
                ;;
            "")
                print_message $RED "错误: monitor 命令需要子命令"
                echo "可用子命令: start, stop, status, logs, watch"
                ;;
            *)
                print_message $RED "错误: 未知的 monitor 子命令 '$2'"
                echo "可用子命令: start, stop, status, logs, watch"
                ;;
        esac
        ;;
    "help" | "--help" | "-h")
        show_help
        ;;
    "")
        show_help
        ;;
    *)
        print_message $RED "错误: 未知命令 '$1'"
        echo
        show_help
        exit 1
        ;;
esac