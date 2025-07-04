#!/bin/bash

# Nexus CLI 多开管理脚本
# 功能：启动多个Nexus实例，提供监控界面

# 配置参数
MAX_INSTANCES=10
BASE_PORT=8080
LOG_DIR="$HOME/.nexus/logs"
PID_DIR="$HOME/.nexus/pids"
CONFIG_DIR="$HOME/.nexus/instances"
NEXUS_CLI_PATH="$HOME/.nexus/bin/nexus-network"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 初始化目录
init_dirs() {
    mkdir -p "$LOG_DIR" "$PID_DIR" "$CONFIG_DIR"
}

# 检查nexus-cli是否存在
check_nexus_cli() {
    if [ ! -f "$NEXUS_CLI_PATH" ]; then
        echo -e "${RED}错误: 找不到nexus-cli程序: $NEXUS_CLI_PATH${NC}"
        echo -e "${YELLOW}请确保已正确安装nexus-cli${NC}"
        exit 1
    fi
}

# 启动实例
start_instance() {
    local node_id="$1"
    local max_threads="${2:-1}"
    local headless="${3:-false}"
    
    local pid_file="$PID_DIR/nexus_$node_id.pid"
    local log_file="$LOG_DIR/nexus_$node_id.log"
    local config_dir="$CONFIG_DIR/nexus_$node_id"
    
    # 检查实例是否已在运行
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}node-id $node_id 已在运行 (PID: $pid)${NC}"
            return 1
        else
            rm -f "$pid_file"
        fi
    fi
    
    # 创建配置目录
    mkdir -p "$config_dir"
    
    # 构建启动命令
    local cmd="$NEXUS_CLI_PATH start"
    
    # 添加node_id参数
    if [ -n "$node_id" ]; then
        cmd="$cmd --node-id $node_id"
    fi
    
    # 添加headless参数
    if [ "$headless" = "true" ]; then
        cmd="$cmd --headless"
    fi
    
    # 添加max_threads参数
    if [ -n "$max_threads" ] && [ "$max_threads" -gt 0 ]; then
        cmd="$cmd --max-threads $max_threads"
    fi
    
    echo -e "${GREEN}启动 node-id $node_id...${NC}"
    echo -e "${BLUE}命令: $cmd${NC}"
    echo -e "${BLUE}日志文件: $log_file${NC}"
    
    # 启动实例
    cd "$config_dir"
    nohup $cmd > "$log_file" 2>&1 &
    local pid=$!
    echo $pid > "$pid_file"
    
    sleep 2
    
    # 验证启动
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "${GREEN}node-id $node_id 启动成功 (PID: $pid)${NC}"
    else
        echo -e "${RED}node-id $node_id 启动失败${NC}"
        rm -f "$pid_file"
        return 1
    fi
}

# 通过node-id启动实例
start_instance_by_node() {
    local node_id="$1"
    local max_threads="${2:-1}"
    local headless="${3:-true}"
    
    if [ -z "$node_id" ]; then
        echo -e "${RED}错误: 请指定node-id${NC}"
        return 1
    fi
    
    # 直接调用start_instance函数
    start_instance "$node_id" "$max_threads" "$headless"
}

# 停止实例（通过node_id）
stop_instance() {
    local node_id="$1"
    local pid_file="$PID_DIR/nexus_$node_id.pid"
    
    if [ ! -f "$pid_file" ]; then
        echo -e "${YELLOW}node-id $node_id 未运行${NC}"
        return 1
    fi
    
    local pid=$(cat "$pid_file")
    
    echo -e "${YELLOW}停止 node-id $node_id (PID: $pid)...${NC}"
    
    # 尝试优雅停止
    if kill "$pid" 2>/dev/null; then
        # 等待进程结束
        local count=0
        while kill -0 "$pid" 2>/dev/null && [ $count -lt 10 ]; do
            sleep 1
            count=$((count + 1))
        done
        
        # 如果进程仍在运行，强制杀死
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${RED}强制停止 node-id $node_id${NC}"
            kill -9 "$pid" 2>/dev/null
        fi
    fi
    
    # 清理PID文件
    rm -f "$pid_file"
    echo -e "${GREEN}node-id $node_id 已停止${NC}"
}

# 通过node-id停止实例
stop_instance_by_node() {
    local node_id="$1"
    
    if [ -z "$node_id" ]; then
        echo -e "${RED}错误: 请指定node-id${NC}"
        return 1
    fi
    
    # 直接使用node_id查找PID文件
    stop_instance "$node_id"
}

# 停止所有运行中的实例
stop_all_instances() {
    echo -e "${CYAN}停止所有运行中的实例...${NC}"
    
    local stopped_count=0
    local total_count=0
    
    # 遍历所有PID文件
    for pid_file in "$PID_DIR"/nexus_*.pid; do
        if [ -f "$pid_file" ]; then
            # 从文件名提取node_id
            local node_id=$(basename "$pid_file" .pid | sed 's/nexus_//')
            local pid=$(cat "$pid_file")
            
            if kill -0 "$pid" 2>/dev/null; then
                total_count=$((total_count + 1))
                echo -e "${YELLOW}停止 node-id $node_id (PID: $pid)...${NC}"
                stop_instance "$node_id"
                if [ $? -eq 0 ]; then
                    stopped_count=$((stopped_count + 1))
                fi
            else
                # 清理无效的PID文件
                rm -f "$pid_file"
            fi
        fi
    done
    
    if [ $total_count -eq 0 ]; then
        echo -e "${YELLOW}没有运行中的实例${NC}"
    else
        echo -e "${GREEN}停止完成: 成功停止 $stopped_count/$total_count 个实例${NC}"
    fi
}

# 启动所有配置的node-id实例
start_all_instances() {
    echo -e "${CYAN}启动所有配置的实例...${NC}"
    
    # 从startup_template.sh读取NODE_IDS配置
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local startup_template="$script_dir/startup_template.sh"
    
    if [ ! -f "$startup_template" ]; then
        echo -e "${RED}错误: 找不到 startup_template.sh 文件${NC}"
        return 1
    fi
    
    # 提取NODE_IDS数组
    local node_ids_line=$(grep -A 20 "NODE_IDS=(" "$startup_template" | grep -E "^[[:space:]]*\"[0-9]+\"" | sed 's/.*"\([0-9]*\)".*/\1/')
    
    if [ -z "$node_ids_line" ]; then
        echo -e "${RED}错误: 在 startup_template.sh 中未找到有效的 NODE_IDS 配置${NC}"
        return 1
    fi
    
    local total_count=0
    local started_count=0
    
    # 逐个启动每个node-id
    while IFS= read -r node_id; do
        if [ -n "$node_id" ]; then
            total_count=$((total_count + 1))
            echo -e "${BLUE}启动 node-id: $node_id${NC}"
            if start_instance_by_node "$node_id" "1" "true"; then
                started_count=$((started_count + 1))
                sleep 1  # 避免同时启动过多实例
            fi
        fi
    done <<< "$node_ids_line"
    
    if [ $total_count -eq 0 ]; then
        echo -e "${YELLOW}没有找到配置的 node-id${NC}"
    else
        echo -e "${GREEN}启动完成: 成功启动 $started_count/$total_count 个实例${NC}"
    fi
}

# 通过node-id重启实例
restart_instance_by_node() {
    local node_id="$1"
    local max_threads="${2:-1}"
    
    if [ -z "$node_id" ]; then
        echo -e "${RED}错误: 请指定node-id${NC}"
        return 1
    fi
    
    echo -e "${CYAN}重启 node-id $node_id...${NC}"
    
    # 先停止实例
    stop_instance_by_node "$node_id"
    
    # 等待2秒
    sleep 2
    
    # 直接使用node_id重新启动
    echo -e "${GREEN}重新启动 node-id $node_id${NC}"
    start_instance "$node_id" "$max_threads" "true"
}

# 批量停止指定node-id的实例
batch_stop_by_nodes() {
    local node_ids="$1"
    
    if [ -z "$node_ids" ]; then
        echo -e "${RED}错误: 请指定node-id列表（用逗号分隔）${NC}"
        return 1
    fi
    
    echo -e "${CYAN}批量停止指定的node-id实例...${NC}"
    
    # 将逗号分隔的字符串转换为数组
    IFS=',' read -ra NODE_ARRAY <<< "$node_ids"
    
    for node_id in "${NODE_ARRAY[@]}"; do
        # 去除空格
        node_id=$(echo "$node_id" | tr -d ' ')
        if [ -n "$node_id" ]; then
            echo -e "${BLUE}停止 node-id: $node_id${NC}"
            stop_instance_by_node "$node_id"
        fi
    done
    
    echo -e "${GREEN}批量停止操作完成${NC}"
}

# 获取实例状态
get_instance_status() {
    local node_id="$1"
    local pid_file="$PID_DIR/nexus_$node_id.pid"
    
    if [ ! -f "$pid_file" ]; then
        echo "STOPPED"
        return
    fi
    
    local pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
        echo "RUNNING"
    else
        echo "DEAD"
    fi
}

# 显示所有实例状态
show_status() {
    echo -e "${CYAN}=== NEXUS 多实例状态监控 ===${NC}"
    echo -e "${BLUE}时间: $(date)${NC}"
    echo ""
    
    printf "%-12s %-10s %-8s %-15s %-20s\n" "Node-ID" "状态" "PID" "CPU使用率" "内存使用"
    echo "----------------------------------------------------------------"
    
    local total_instances=0
    local running_count=0
    
    # 遍历所有PID文件
    for pid_file in "$PID_DIR"/nexus_*.pid; do
        if [ -f "$pid_file" ]; then
            # 从文件名提取node_id
            local node_id=$(basename "$pid_file" .pid | sed 's/nexus_//')
            local status=$(get_instance_status "$node_id")
            local pid="-"
            local cpu="-"
            local mem="-"
            
            total_instances=$((total_instances + 1))
            
            if [ "$status" = "RUNNING" ]; then
                running_count=$((running_count + 1))
                pid=$(cat "$pid_file")
                # 获取CPU和内存使用率
                if command -v ps >/dev/null 2>&1; then
                    local ps_output=$(ps -p "$pid" -o pcpu,pmem --no-headers 2>/dev/null)
                    if [ -n "$ps_output" ]; then
                        cpu=$(echo "$ps_output" | awk '{print $1"%"}')
                        mem=$(echo "$ps_output" | awk '{print $2"%"}')
                    fi
                fi
            fi
            
            # 根据状态设置颜色
            case $status in
                "RUNNING")
                    printf "%-12s ${GREEN}%-10s${NC} %-8s %-15s %-20s\n" "$node_id" "$status" "$pid" "$cpu" "$mem"
                    ;;
                "DEAD")
                    printf "%-12s ${RED}%-10s${NC} %-8s %-15s %-20s\n" "$node_id" "$status" "$pid" "$cpu" "$mem"
                    ;;
                *)
                    printf "%-12s ${YELLOW}%-10s${NC} %-8s %-15s %-20s\n" "$node_id" "$status" "$pid" "$cpu" "$mem"
                    ;;
            esac
        fi
    done
    
    # 如果没有找到任何PID文件，显示提示信息
    if [ $total_instances -eq 0 ]; then
        echo -e "${YELLOW}没有找到任何实例${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}总实例数: $total_instances${NC}"
    echo -e "${GREEN}运行中: $running_count${NC}"
    echo -e "${RED}已停止: $((total_instances - running_count))${NC}"
}

# 显示实例日志
show_logs() {
    local instance_id="$1"
    local lines="${2:-50}"
    local log_file="$LOG_DIR/nexus_$instance_id.log"
    
    if [ ! -f "$log_file" ]; then
        echo -e "${RED}日志文件不存在: $log_file${NC}"
        return 1
    fi
    
    echo -e "${CYAN}=== 实例 $instance_id 日志 (最近 $lines 行) ===${NC}"
    tail -n "$lines" "$log_file"
}

# 通过node-id显示日志
show_logs_by_node() {
    local node_id="$1"
    local lines="${2:-50}"
    
    if [ -z "$node_id" ]; then
        echo -e "${RED}错误: 请指定node-id${NC}"
        return 1
    fi
    
    local log_file="$LOG_DIR/nexus_$node_id.log"
    
    # 直接检查该node-id的日志文件是否存在
    if [ -f "$log_file" ]; then
        echo -e "${GREEN}显示 node-id $node_id 的日志${NC}"
        echo "日志文件: $log_file"
        echo "==========================================="
        if [ "$lines" -gt 0 ]; then
            tail -n "$lines" "$log_file"
        else
            cat "$log_file"
        fi
    else
        echo -e "${YELLOW}未找到 node-id $node_id 的日志文件${NC}"
        return 1
    fi
}

# 实时监控模式
monitor_mode() {
    echo -e "${CYAN}进入实时监控模式 (按 Ctrl+C 退出)${NC}"
    echo ""
    
    while true; do
        clear
        show_status
        echo ""
        echo -e "${BLUE}刷新间隔: 5秒${NC}"
        sleep 5
    done
}

# 批量启动实例
batch_start() {
    local node_ids="$1"
    local max_threads="${2:-1}"
    
    if [ -z "$node_ids" ]; then
        echo -e "${RED}错误: 请指定node-id列表（用逗号分隔）${NC}"
        return 1
    fi
    
    echo -e "${CYAN}批量启动实例...${NC}"
    
    # 将逗号分隔的字符串转换为数组
    IFS=',' read -ra NODE_ARRAY <<< "$node_ids"
    
    for node_id in "${NODE_ARRAY[@]}"; do
        # 去除空格
        node_id=$(echo "$node_id" | tr -d ' ')
        if [ -n "$node_id" ]; then
            echo -e "${BLUE}启动 node-id: $node_id${NC}"
            start_instance_by_node "$node_id" "$max_threads" "true"
            sleep 1  # 避免同时启动过多实例
        fi
    done
    
    echo -e "${GREEN}批量启动操作完成${NC}"
}

# 批量停止所有实例
batch_stop() {
    echo -e "${CYAN}批量停止所有实例...${NC}"
    
    for i in $(seq 1 $MAX_INSTANCES); do
        local pid_file="$PID_DIR/nexus_$i.pid"
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file")
            if kill -0 "$pid" 2>/dev/null; then
                stop_instance "$i"
            else
                rm -f "$pid_file"
            fi
        fi
    done
    
    echo -e "${GREEN}所有实例已停止${NC}"
}

# 显示帮助信息
show_help() {
    echo -e "${CYAN}Nexus CLI 多开管理脚本${NC}"
    echo ""
    echo "用法: $0 [命令] [参数]"
    echo ""
    echo "命令:"
    echo "  start [实例ID] [选项]            - 启动指定实例，不带参数则启动所有配置的实例"
    echo "  start-by-node <node-id> [线程数] [无头模式] - 通过node-id启动实例"
    echo "  stop [实例ID]                    - 停止指定实例，不带参数则停止所有实例"
    echo "  stop-by-node <node-id>           - 通过node-id停止实例"
    echo "  restart-by-node <node-id> [线程数] - 通过node-id重启实例"
    echo "  restart <实例ID> [选项]          - 重启指定实例"
    echo "  status                           - 显示所有实例状态"
    echo "  logs <实例ID> [行数]             - 显示实例日志"
    echo "  logs-by-node <node-id> [行数]    - 通过node-id显示日志"
    echo "  monitor                          - 实时监控模式"
    echo "  batch-start <node-ids> [线程数]   - 批量启动实例（node-ids用逗号分隔）"
    echo "  batch-stop                       - 批量停止所有实例"
    echo "  batch-stop-by-nodes <node-ids>   - 批量停止指定的node-id实例（用逗号分隔）"
    echo "  clean                            - 清理死进程和PID文件"
    echo "  help                             - 显示此帮助信息"
    echo ""
    echo "start/restart 命令选项:"
    echo "  --node-id <节点ID>               - 指定节点ID"
    echo "  --max-threads <线程数>           - 指定最大线程数 (默认: 1)"
    echo "  --headless                       - 启用无头模式 (默认启用)"
    echo ""
    echo "示例:"
    echo "  $0 start 1 --max-threads 2                           # 启动实例1，使用2个线程"
    echo "  $0 start 2 --max-threads 4 --node-id 123456         # 启动实例2，使用4个线程，节点ID为123456"
    echo "  $0 start 3 --node-id 789012 --max-threads 3         # 启动实例3，节点ID为789012，使用3个线程"
    echo "  $0 start-by-node 123456 2                           # 通过node-id启动实例，使用2个线程"
    echo "  $0 restart 1 --node-id 456789                       # 重启实例1，使用新的节点ID"
    echo "  $0 restart-by-node 123456 2                         # 通过node-id重启实例，使用2个线程"
    echo "  $0 batch-start \"123456,789012,345678,901234,567890\" 2  # 批量启动5个实例，使用指定的node-id，每个使用2个线程"
    echo "  $0 batch-stop-by-nodes \"123456,789012,345678\"       # 批量停止指定的node-id实例"
    echo "  $0 monitor                                           # 进入实时监控模式"
    echo "  $0 logs 1 100                                       # 显示实例1的最近100行日志"
    echo "  $0 logs-by-node 123456 50                           # 显示node-id为123456的最近50行日志"
    echo ""
    echo "注意:"
    echo "  - 节点ID必须是纯数字格式"
    echo "  - 推荐使用 startup_template.sh 进行批量配置和管理"
    echo "  - 每个实例会使用独立的配置目录: ~/.nexus_<实例ID>"
}

# 清理死进程和PID文件
clean_dead_processes() {
    echo -e "${YELLOW}清理死进程和PID文件...${NC}"
    
    for i in $(seq 1 $MAX_INSTANCES); do
        local pid_file="$PID_DIR/nexus_$i.pid"
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file")
            if ! kill -0 "$pid" 2>/dev/null; then
                echo -e "${YELLOW}清理死进程文件: $pid_file (PID: $pid)${NC}"
                rm -f "$pid_file"
            fi
        fi
    done
    
    echo -e "${GREEN}清理完成${NC}"
}

# 解析启动参数
parse_start_args() {
    local instance_id="$1"
    shift
    
    local max_threads="1"
    local node_id=""
    local headless="false"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --node-id)
                node_id="$2"
                shift 2
                ;;
            --max-threads)
                max_threads="$2"
                shift 2
                ;;
            --headless)
                headless="true"
                shift
                ;;
            *)
                echo -e "${RED}错误: 未知参数 '$1'${NC}"
                exit 1
                ;;
        esac
    done
    
    if [ -z "$node_id" ]; then
        echo -e "${RED}错误: 请指定--node-id参数${NC}"
        exit 1
    fi
    start_instance "$node_id" "$max_threads" "$headless"
}

# 主函数
main() {
    init_dirs
    check_nexus_cli
    
    case "${1:-help}" in
        "start")
            if [ -z "$2" ]; then
                start_all_instances
            else
                parse_start_args "${@:2}"
            fi
            ;;
        "start-by-node")
            if [ -z "$2" ]; then
                echo -e "${RED}错误: 请指定node-id${NC}"
                show_help
                exit 1
            fi
            start_instance_by_node "$2" "$3" "$4"
            ;;
        "stop")
            if [ -z "$2" ]; then
                stop_all_instances
            else
                stop_instance "$2"
            fi
            ;;
        "stop-by-node")
            if [ -z "$2" ]; then
                echo -e "${RED}错误: 请指定node-id${NC}"
                show_help
                exit 1
            fi
            stop_instance_by_node "$2"
            ;;
        "restart")
            if [ -z "$2" ]; then
                echo -e "${RED}错误: 请指定node-id${NC}"
                show_help
                exit 1
            fi
            local node_id="$2"
            local max_threads="1"
            # 解析--max-threads参数
            if [ "$3" = "--max-threads" ] && [ -n "$4" ]; then
                max_threads="$4"
            fi
            restart_instance_by_node "$node_id" "$max_threads"
            ;;
        "restart-by-node")
            if [ -z "$2" ]; then
                echo -e "${RED}错误: 请指定node-id${NC}"
                show_help
                exit 1
            fi
            restart_instance_by_node "$2" "$3"
            ;;
        "status")
            show_status
            ;;
        "logs")
            if [ -z "$2" ]; then
                echo -e "${RED}错误: 请指定实例ID${NC}"
                show_help
                exit 1
            fi
            show_logs "$2" "$3"
            ;;
        "logs-by-node")
            if [ -z "$2" ]; then
                echo -e "${RED}错误: 请指定node-id${NC}"
                show_help
                exit 1
            fi
            show_logs_by_node "$2" "$3"
            ;;
        "monitor")
            monitor_mode
            ;;
        "batch-start")
            if [ -z "$2" ]; then
                echo -e "${RED}错误: 请指定node-id列表（用逗号分隔）${NC}"
                show_help
                exit 1
            fi
            batch_start "$2" "$3"
            ;;
        "batch-stop")
            batch_stop
            ;;
        "batch-stop-by-nodes")
            if [ -z "$2" ]; then
                echo -e "${RED}错误: 请指定node-id列表（用逗号分隔）${NC}"
                show_help
                exit 1
            fi
            batch_stop_by_nodes "$2"
            ;;
        "clean")
            clean_dead_processes
            ;;
        "help")
            show_help
            ;;
        *)
            echo -e "${RED}错误: 未知命令 '$1'${NC}"
            show_help
            exit 1
            ;;
    esac
}

# 捕获Ctrl+C信号
trap 'echo -e "\n${YELLOW}脚本已退出${NC}"; exit 0' INT

# 运行主函数
main "$@"