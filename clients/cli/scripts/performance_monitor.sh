#!/bin/bash

# Nexus CLI 性能监控脚本
# 监控队列状态、任务处理效率和"Queue low"问题

# =============================================================================
# 配置区域
# =============================================================================

# 监控配置
MONITOR_INTERVAL=10        # 检查间隔（秒）
LOG_RETENTION_DAYS=7       # 监控日志保留天数
PERFORMANCE_LOG_DIR="$HOME/.nexus/performance_logs"
QUEUE_EMPTY_THRESHOLD=5    # 队列为空连续次数阈值

# 路径配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$HOME/.nexus/logs"

# 创建必要目录
mkdir -p "$PERFORMANCE_LOG_DIR" "$LOG_DIR"

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

# 记录性能监控日志
log_performance() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="$PERFORMANCE_LOG_DIR/performance_$(date '+%Y%m%d').log"
    
    echo "[$timestamp] [$level] $message" >> "$log_file"
    
    # 同时输出到控制台
    case $level in
        "INFO")
            echo -e "${GREEN}[$timestamp] [INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[$timestamp] [ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[$timestamp] [DEBUG]${NC} $message"
            ;;
        *)
            echo "[$timestamp] [$level] $message"
            ;;
    esac
}

# =============================================================================
# 性能分析函数
# =============================================================================

# 分析队列状态
analyze_queue_status() {
    local log_file="$1"
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 统计队列状态
    local queue_empty_count=$(grep -c "Queue low: 0" "$log_file" 2>/dev/null || echo 0)
    local queue_low_count=$(grep -c "Queue low:" "$log_file" 2>/dev/null || echo 0)
    local force_fetch_count=$(grep -c "Force fetching" "$log_file" 2>/dev/null || echo 0)
    local empty_fetches_count=$(grep -c "empty fetches:" "$log_file" 2>/dev/null || echo 0)
    
    # 计算队列效率
    local total_checks=$((queue_low_count + force_fetch_count))
    local efficiency=0
    if [ $total_checks -gt 0 ]; then
        efficiency=$((100 - (queue_empty_count * 100 / total_checks)))
    fi
    
    log_performance "INFO" "队列状态分析:"
    log_performance "INFO" "  - 队列为空次数: $queue_empty_count"
    log_performance "INFO" "  - 队列低水位次数: $queue_low_count"
    log_performance "INFO" "  - 强制获取次数: $force_fetch_count"
    log_performance "INFO" "  - 空获取次数: $empty_fetches_count"
    log_performance "INFO" "  - 队列效率: ${efficiency}%"
    
    # 检查是否需要优化
    if [ $queue_empty_count -gt $QUEUE_EMPTY_THRESHOLD ]; then
        log_performance "WARN" "检测到频繁的队列为空情况，建议检查网络连接或服务器状态"
    fi
    
    if [ $efficiency -lt 70 ]; then
        log_performance "WARN" "队列效率较低 (${efficiency}%)，建议优化任务获取策略"
    fi
}

# 分析任务处理效率
analyze_task_processing() {
    local log_file="$1"
    
    # 统计任务处理情况
    local proof_completed=$(grep -c "Proof completed successfully" "$log_file" 2>/dev/null || echo 0)
    local proof_errors=$(grep -c "Error:" "$log_file" 2>/dev/null || echo 0)
    local fetch_errors=$(grep -c "Failed to fetch tasks" "$log_file" 2>/dev/null || echo 0)
    
    # 计算成功率
    local total_operations=$((proof_completed + proof_errors))
    local success_rate=0
    if [ $total_operations -gt 0 ]; then
        success_rate=$((proof_completed * 100 / total_operations))
    fi
    
    log_performance "INFO" "任务处理分析:"
    log_performance "INFO" "  - 成功完成证明: $proof_completed"
    log_performance "INFO" "  - 证明错误: $proof_errors"
    log_performance "INFO" "  - 获取任务错误: $fetch_errors"
    log_performance "INFO" "  - 成功率: ${success_rate}%"
    
    # 检查性能问题
    if [ $success_rate -lt 90 ]; then
        log_performance "WARN" "任务处理成功率较低 (${success_rate}%)，建议检查系统资源"
    fi
}

# 分析退避策略效果
analyze_backoff_strategy() {
    local log_file="$1"
    
    # 统计退避情况
    local backoff_increases=$(grep -c "backing off" "$log_file" 2>/dev/null || echo 0)
    local backoff_resets=$(grep -c "reset backoff" "$log_file" 2>/dev/null || echo 0)
    local waiting_messages=$(grep -c "waiting.*s more" "$log_file" 2>/dev/null || echo 0)
    
    log_performance "INFO" "退避策略分析:"
    log_performance "INFO" "  - 退避增加次数: $backoff_increases"
    log_performance "INFO" "  - 退避重置次数: $backoff_resets"
    log_performance "INFO" "  - 等待消息次数: $waiting_messages"
    
    # 检查退避策略是否合理
    if [ $backoff_increases -gt $((backoff_resets * 2)) ]; then
        log_performance "WARN" "退避策略可能过于激进，建议调整退避参数"
    fi
}

# =============================================================================
# 主监控函数
# =============================================================================

# 监控单个实例
monitor_instance() {
    local node_id=$1
    local log_file="$LOG_DIR/nexus_${node_id}.log"
    
    if [ ! -f "$log_file" ]; then
        log_performance "WARN" "实例 $node_id 的日志文件不存在: $log_file"
        return
    fi
    
    log_performance "INFO" "开始监控实例 $node_id..."
    
    # 分析各项指标
    analyze_queue_status "$log_file"
    analyze_task_processing "$log_file"
    analyze_backoff_strategy "$log_file"
    
    log_performance "INFO" "实例 $node_id 监控完成"
}

# 监控所有实例
monitor_all_instances() {
    log_performance "INFO" "开始性能监控..."
    
    # 获取所有运行中的实例
    local instances=()
    local node_ids=$(ps -ef | grep -v grep | grep "nexus-network start" | grep -o "node-id [0-9]*" | awk '{print $2}' | sort -u)
    
    if [ -z "$node_ids" ]; then
        log_performance "WARN" "未发现运行中的 Nexus 实例"
        return
    fi
    
    for node_id in $node_ids; do
        instances+=($node_id)
    done
    
    log_performance "INFO" "发现 ${#instances[@]} 个运行中的实例: ${instances[*]}"
    
    # 监控每个实例
    for node_id in "${instances[@]}"; do
        monitor_instance "$node_id"
        echo "----------------------------------------"
    done
}

# =============================================================================
# 清理旧日志
# =============================================================================

cleanup_old_logs() {
    log_performance "INFO" "清理 $LOG_RETENTION_DAYS 天前的旧日志..."
    
    # 清理性能日志
    find "$PERFORMANCE_LOG_DIR" -name "performance_*.log" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
    
    # 清理实例日志
    find "$LOG_DIR" -name "nexus_*.log" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
    
    log_performance "INFO" "日志清理完成"
}

# =============================================================================
# 主程序
# =============================================================================

main() {
    echo -e "${CYAN}🚀 Nexus CLI 性能监控器${NC}"
    echo "========================================"
    
    # 检查参数
    case "${1:-}" in
        "cleanup")
            cleanup_old_logs
            exit 0
            ;;
        "help"|"-h"|"--help")
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  cleanup    清理旧日志"
            echo "  help       显示帮助信息"
            echo ""
            echo "示例:"
            echo "  $0           # 执行性能监控"
            echo "  $0 cleanup   # 清理旧日志"
            exit 0
            ;;
    esac
    
    # 执行监控
    monitor_all_instances
    
    # 定期清理
    if [ $((RANDOM % 10)) -eq 0 ]; then
        cleanup_old_logs
    fi
    
    log_performance "INFO" "性能监控完成"
}

# 捕获中断信号
trap 'echo -e "\n${YELLOW}监控被中断${NC}"; exit 0' INT TERM

# 运行主程序
main "$@" 