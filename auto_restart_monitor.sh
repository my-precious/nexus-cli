#!/bin/bash

# Nexus CLI 自动重启监控脚本
# 监控日志中的 "Performance: 0" 并在出现3次时自动重启实例

# =============================================================================
# 配置区域auto_restart_monitor.sh
# =============================================================================

# 监控配置
MONITOR_INTERVAL=30        # 检查间隔（秒）
PERFORMANCE_ZERO_THRESHOLD=3  # Performance: 0 触发重启的次数阈值
LOG_RETENTION_DAYS=2       # 监控日志保留天数
MAX_RESTART_ATTEMPTS=300000     # 最大重启尝试次数
RESTART_COOLDOWN=60        # 重启冷却时间（秒）

# 路径配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MULTI_RUNNER="$SCRIPT_DIR/nexus_multi_runner.sh"
LOG_DIR="$HOME/.nexus/logs"
MONITOR_LOG_DIR="$SCRIPT_DIR/monitor_logs"
STATE_DIR="$SCRIPT_DIR/monitor_state"

# 创建必要目录
mkdir -p "$MONITOR_LOG_DIR" "$STATE_DIR"

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
# 日志函数
# =============================================================================

# 记录监控日志
log_monitor() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="$MONITOR_LOG_DIR/auto_restart_$(date '+%Y%m%d').log"
    
    echo "[$timestamp] [$level] $message" >> "$log_file"
    
    # 同时输出到控制台（如果不是后台运行）
    if [[ -t 1 ]]; then
        case $level in
            "ERROR")
                echo -e "${RED}[$timestamp] [$level] $message${NC}"
                ;;
            "WARN")
                echo -e "${YELLOW}[$timestamp] [$level] $message${NC}"
                ;;
            "INFO")
                echo -e "${GREEN}[$timestamp] [$level] $message${NC}"
                ;;
            "DEBUG")
                echo -e "${CYAN}[$timestamp] [$level] $message${NC}"
                ;;
            *)
                echo "[$timestamp] [$level] $message"
                ;;
        esac
    fi
}

# =============================================================================
# 状态管理函数
# =============================================================================

# 获取实例状态文件路径
get_state_file() {
    local instance_id=$1
    echo "$STATE_DIR/instance_${instance_id}_state.json"
}

# 初始化实例状态
init_instance_state() {
    local instance_id=$1
    local state_file=$(get_state_file $instance_id)
    
    if [[ ! -f "$state_file" ]]; then
        cat > "$state_file" << EOF
{
  "instance_id": "$instance_id",
  "first_performance_zero_time": null,
  "last_performance_zero_time": null,
  "performance_zero_count": 0,
  "restart_count": 0,
  "last_restart_time": null,
  "status": "monitoring",
  "success_task_count": 0
}
EOF
        log_monitor "INFO" "初始化实例 $instance_id 状态文件"
    fi
}

# 读取实例状态
read_instance_state() {
    local instance_id=$1
    local state_file=$(get_state_file $instance_id)
    
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        init_instance_state $instance_id
        cat "$state_file"
    fi
}

# 更新实例状态
update_instance_state() {
    local instance_id=$1
    local key=$2
    local value=$3
    local state_file=$(get_state_file $instance_id)
    
    # 使用临时文件更新JSON
    local temp_file="${state_file}.tmp"
    
    if command -v jq >/dev/null 2>&1; then
        # 使用jq更新（如果可用）
        if [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" == "null" ]]; then
            # 数值或null类型，不加引号
            jq ".$key = $value" "$state_file" > "$temp_file" && mv "$temp_file" "$state_file"
        else
            # 字符串类型，加引号
            jq ".$key = \"$value\"" "$state_file" > "$temp_file" && mv "$temp_file" "$state_file"
        fi
    else
        # 简单的sed替换（备用方案）
        if [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" == "null" ]]; then
            # 数值或null类型
            sed "s/\"$key\": [^,}]*/\"$key\": $value/g" "$state_file" > "$temp_file" && mv "$temp_file" "$state_file"
        else
            # 字符串类型
            sed "s/\"$key\": \"[^\"]*\"/\"$key\": \"$value\"/g" "$state_file" > "$temp_file" && mv "$temp_file" "$state_file"
        fi
    fi
}

# =============================================================================
# 监控函数
# =============================================================================

# 检查实例是否运行
is_instance_running() {
    local node_id=$1
    
    # 检查PID文件方式
    local pid_file="$HOME/.nexus/pids/nexus_${node_id}.pid"
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    
    return 1
}

# 根据node_id获取对应的instance_id（实际上就是node_id本身）
get_instance_id_by_node_id() {
    local node_id=$1
    
    # 检查对应的PID文件是否存在
    local pid_file="$HOME/.nexus/pids/nexus_${node_id}.pid"
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        # 检查进程是否还在运行
        if kill -0 "$pid" 2>/dev/null; then
            echo "$node_id"
            return 0
        fi
    fi
    
    return 1
}

# 检查日志中的Performance: 0
check_performance_zero() {
    local node_id=$1
    
    # 直接使用node_id作为日志文件名
    local log_file="$LOG_DIR/nexus_${node_id}.log"
    
    if [[ ! -f "$log_file" ]]; then
        log_monitor "DEBUG" "日志文件不存在: $log_file"
        return 1
    fi
    
    # 检查最近的日志中是否有Performance: 0
    local recent_logs=$(tail -n 10 "$log_file" | grep -c "Performance: 0")
    
    if [[ $recent_logs -gt 0 ]]; then
        log_monitor "DEBUG" "在 $log_file 中检测到 $recent_logs 条 Performance: 0 记录"
        return 0
    else
        return 1
    fi
}

# 重启实例
restart_instance() {
    local node_id=$1
    local state_file=$(get_state_file $node_id)
    
    log_monitor "WARN" "准备重启实例 node_id $node_id (检测到连续Performance: 0)"
    
    # 检查重启冷却时间
    local last_restart=$(jq -r '.last_restart_time // "null"' "$state_file" 2>/dev/null || echo "null")
    if [[ "$last_restart" != "null" ]]; then
        # macOS兼容的时间戳转换
        local last_restart_timestamp
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS使用不同的date格式
            last_restart_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$last_restart" +%s 2>/dev/null || echo 0)
        else
            # Linux使用-d参数
            last_restart_timestamp=$(date -d "$last_restart" +%s 2>/dev/null || echo 0)
        fi
        
        local current_timestamp=$(date +%s)
        local time_diff=$((current_timestamp - last_restart_timestamp))
        
        if [[ $time_diff -lt $RESTART_COOLDOWN ]]; then
            log_monitor "WARN" "实例 node_id $node_id 在冷却期内，跳过重启 (剩余 $((RESTART_COOLDOWN - time_diff)) 秒)"
            return 1
        fi
    fi
    
    # 检查最大重启次数
    local restart_count=$(jq -r '.restart_count // 0' "$state_file" 2>/dev/null || echo 0)
    if [[ $restart_count -ge $MAX_RESTART_ATTEMPTS ]]; then
        log_monitor "ERROR" "实例 node_id $node_id 已达到最大重启次数 ($MAX_RESTART_ATTEMPTS)，停止自动重启"
        update_instance_state $node_id "status" "max_restarts_reached"
        return 1
    fi
    
    # 执行重启
    log_monitor "INFO" "正在重启实例 node_id $node_id..."
    
    if "$MULTI_RUNNER" restart "$node_id"; then
        local current_time=$(date '+%Y-%m-%d %H:%M:%S')
        update_instance_state $node_id "last_restart_time" "$current_time"
        update_instance_state $node_id "restart_count" "$((restart_count + 1))"
        update_instance_state $node_id "first_performance_zero_time" "null"
        update_instance_state $node_id "performance_zero_count" "0"
        update_instance_state $node_id "status" "restarted"
        
        log_monitor "INFO" "实例 node_id $node_id 重启成功 (第 $((restart_count + 1)) 次重启)"
        return 0
    else
        log_monitor "ERROR" "实例 node_id $node_id 重启失败"
        return 1
    fi
}

# 监控单个实例
monitor_instance() {
    local node_id=$1
    
    # 初始化状态
    init_instance_state $node_id
    
    # 检查实例是否运行
    if ! is_instance_running $node_id; then
        log_monitor "DEBUG" "实例 node_id $node_id 未运行，跳过监控"
        return 0
    fi
    
    local state_file=$(get_state_file $node_id)
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    local current_timestamp=$(date +%s)
    
    # 检查是否有Performance: 0
    if check_performance_zero $node_id; then
        log_monitor "DEBUG" "实例 node_id $node_id 检测到 Performance: 0"
        
        # 获取当前状态
        local count=$(jq -r '.performance_zero_count // 0' "$state_file" 2>/dev/null || echo 0)
        local new_count=$((count + 1))
        
        # 更新计数和最后检测时间
        update_instance_state $node_id "performance_zero_count" "$new_count"
        update_instance_state $node_id "last_performance_zero_time" "$current_time"
        
        log_monitor "WARN" "实例 node_id $node_id 检测到 Performance: 0，当前计数: $new_count/$PERFORMANCE_ZERO_THRESHOLD"
        
        # 检查是否达到重启阈值
        if [[ $new_count -ge $PERFORMANCE_ZERO_THRESHOLD ]]; then
            log_monitor "WARN" "实例 node_id $node_id Performance: 0 出现 $new_count 次，达到阈值 $PERFORMANCE_ZERO_THRESHOLD，触发重启条件"
            restart_instance $node_id
        fi
    else
        # 没有Performance: 0，重置状态
        local count=$(jq -r '.performance_zero_count // 0' "$state_file" 2>/dev/null || echo 0)
        if [[ $count -gt 0 ]]; then
            update_instance_state $node_id "performance_zero_count" "0"
            update_instance_state $node_id "status" "monitoring"
            log_monitor "INFO" "实例 node_id $node_id 恢复正常，重置监控状态（之前计数: $count）"
        fi
    fi
}

# =============================================================================
# 主监控循环
# =============================================================================

# 获取所有运行中的实例
get_running_instances() {
    local instances=()
    
    # 直接从进程中提取node-id
    local node_ids=$(ps -ef | grep -v grep | grep "nexus-network start" | grep -o "node-id [0-9]*" | awk '{print $2}' | sort -u)
    
    for node_id in $node_ids; do
        instances+=($node_id)
    done
    
    echo "${instances[@]}"
}

# 主监控函数
start_monitoring() {
    log_monitor "INFO" "启动自动重启监控服务"
    log_monitor "INFO" "监控间隔: ${MONITOR_INTERVAL}秒"
    log_monitor "INFO" "Performance: 0 触发阈值: ${PERFORMANCE_ZERO_THRESHOLD}次"
    log_monitor "INFO" "最大重启次数: $MAX_RESTART_ATTEMPTS"
    
    while true; do
        local instances=($(get_running_instances))
        
        if [[ ${#instances[@]} -eq 0 ]]; then
            log_monitor "DEBUG" "没有检测到运行中的实例"
        else
            log_monitor "DEBUG" "监控实例: ${instances[*]}"
            
            for instance_id in "${instances[@]}"; do
                monitor_instance $instance_id
            done
        fi
        
        sleep $MONITOR_INTERVAL
    done
}

# 停止监控
stop_monitoring() {
    local pid_file="$STATE_DIR/monitor.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$pid_file"
            log_monitor "INFO" "监控服务已停止"
        else
            rm -f "$pid_file"
            log_monitor "WARN" "监控服务PID文件存在但进程不存在"
        fi
    else
        log_monitor "WARN" "监控服务未运行"
    fi
}

# 显示监控日志
show_monitor_logs() {
    local lines="${1:-100}"
    
    echo -e "${CYAN}=== 监控日志 (最近 $lines 行) ===${NC}"
    echo
    
    # 查找最新的监控日志文件
    local latest_log=$(find "$MONITOR_LOG_DIR" -name "auto_restart_*.log" -type f 2>/dev/null | sort | tail -n 1)
    
    if [[ -n "$latest_log" && -f "$latest_log" ]]; then
        echo -e "${GREEN}显示日志文件: $latest_log${NC}"
        echo
        tail -n "$lines" "$latest_log"
    else
        echo -e "${YELLOW}监控日志文件不存在${NC}"
        echo "监控日志目录: $MONITOR_LOG_DIR"
    fi
    
    echo
    echo -e "${YELLOW}所有日志文件:${NC}"
    if [[ -d "$MONITOR_LOG_DIR" ]]; then
        ls -la "$MONITOR_LOG_DIR/" 2>/dev/null || echo "监控日志目录为空"
    else
        echo "监控日志目录不存在: $MONITOR_LOG_DIR"
    fi
}

# 显示监控状态
show_monitor_status() {
    local pid_file="$STATE_DIR/monitor.pid"
    
    echo -e "${CYAN}=== 自动重启监控状态 ===${NC}"
    echo
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${GREEN}监控服务状态: 运行中 (PID: $pid)${NC}"
        else
            echo -e "${RED}监控服务状态: 已停止 (PID文件存在但进程不存在)${NC}"
        fi
    else
        echo -e "${YELLOW}监控服务状态: 未运行${NC}"
    fi
    
    echo
    echo -e "${BLUE}配置信息:${NC}"
    echo "  - 监控间隔: ${MONITOR_INTERVAL}秒"
    echo "  - Performance: 0 触发阈值: ${PERFORMANCE_ZERO_THRESHOLD}次"
    echo "  - 最大重启次数: $MAX_RESTART_ATTEMPTS"
    echo "  - 重启冷却时间: ${RESTART_COOLDOWN}秒"
    
    echo
    echo -e "${BLUE}实例状态:${NC}"
    
    local instances=($(get_running_instances))
    if [[ ${#instances[@]} -eq 0 ]]; then
        echo "  没有运行中的实例"
    else
        for instance_id in "${instances[@]}"; do
            local state_file=$(get_state_file $instance_id)
            if [[ -f "$state_file" ]]; then
                local status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null || echo "unknown")
                local restart_count=$(jq -r '.restart_count // 0' "$state_file" 2>/dev/null || echo 0)
                local perf_count=$(jq -r '.performance_zero_count // 0' "$state_file" 2>/dev/null || echo 0)
                local log=$(tail -n 1 ~/.nexus/logs/nexus_$instance_id.log)
                # 检查是否有提交任务成功的日志
                if echo "$log" | grep -q "Proof submitted"; then
                    local success_count=$(jq -r '.success_task_count // 0' "$state_file" 2>/dev/null || echo 0)
                    update_instance_state $instance_id "success_task_count" "$((success_count + 1))"
                fi
                
                local success_count=$(cat ~/.nexus/proof_submissions.count | grep $instance_id | awk -F ':' '{print $2}' | tr -d '】')
                echo "  实例 $instance_id: $status (重启次数: $restart_count, Performance: 0 计数: $perf_count, 成功任务数:$success_count) $log"
            else
                echo "  实例 $instance_id: 未监控"
            fi
        done
    fi
}

# 清理旧日志
cleanup_logs() {
    log_monitor "INFO" "清理 $LOG_RETENTION_DAYS 天前的监控日志"
    
    find "$MONITOR_LOG_DIR" -name "auto_restart_*.log" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
    
    log_monitor "INFO" "日志清理完成"
}

# =============================================================================
# 帮助信息
# =============================================================================

show_help() {
    cat << EOF
${CYAN}Nexus CLI 自动重启监控脚本${NC}

${YELLOW}用法:${NC}
  $0 [命令]

${YELLOW}命令:${NC}
  start       启动监控服务（后台运行）
  stop        停止监控服务
  status      显示监控状态
  restart     重启监控服务
  logs [行数]  显示监控日志（默认100行）
  cleanup     清理旧日志文件
  test        测试模式（前台运行）
  help        显示此帮助信息

${YELLOW}功能说明:${NC}
  - 监控所有运行中的Nexus CLI实例日志
  - 检测连续5分钟出现"Performance: 0"的情况
  - 自动重启出现问题的实例
  - 支持重启次数限制和冷却时间
  - 详细的监控日志记录

${YELLOW}配置文件位置:${NC}
  - 监控日志: $MONITOR_LOG_DIR/
  - 状态文件: $STATE_DIR/
  - 实例日志: $LOG_DIR/

${YELLOW}示例:${NC}
  $0 start              # 启动监控服务
  $0 status             # 查看监控状态
  $0 stop               # 停止监控服务

EOF
}

# =============================================================================
# 主程序
# =============================================================================

main() {
    case "${1:-help}" in
        "start")
            local pid_file="$STATE_DIR/monitor.pid"
            
            if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
                echo -e "${YELLOW}监控服务已在运行中${NC}"
                exit 1
            fi
            
            echo -e "${GREEN}启动监控服务...${NC}"
            nohup "$0" _internal_start > "$MONITOR_LOG_DIR/monitor_daemon.log" 2>&1 &
            echo $! > "$pid_file"
            echo -e "${GREEN}监控服务已启动 (PID: $(cat "$pid_file"))${NC}"
            ;;
        "_internal_start")
            # 内部启动命令，用于后台运行
            start_monitoring
            ;;
        "stop")
            stop_monitoring
            ;;
        "restart")
            stop_monitoring
            sleep 2
            "$0" start
            ;;
        "status")
            show_monitor_status
            ;;
        "test")
            echo -e "${YELLOW}测试模式 - 前台运行监控服务${NC}"
            echo -e "${YELLOW}按 Ctrl+C 停止${NC}"
            start_monitoring
            ;;
        "cleanup")
            cleanup_logs
            ;;
        "logs")
            show_monitor_logs "${2:-100}"
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            echo -e "${RED}未知命令: $1${NC}"
            echo
            show_help
            exit 1
            ;;
    esac
}

# 捕获信号
trap 'log_monitor "INFO" "监控服务收到停止信号，正在退出..."; exit 0' TERM INT

# 运行主程序
main "$@"