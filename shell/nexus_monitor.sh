#!/bin/bash

# Nexus CLI 高级监控界面
# 提供实时监控、性能统计、日志查看等功能

# 配置参数
MAX_INSTANCES=10
LOG_DIR="$HOME/.nexus/logs"
PID_DIR="$HOME/.nexus/pids"
REFRESH_INTERVAL=2
LOG_LINES=20

# 颜色和样式定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# Unicode字符
CHECK_MARK="✅"
CROSS_MARK="❌"
WARNING="⚠️"
INFO="ℹ️"
RUNNING="🟢"
STOPPED="🔴"
DEAD="💀"
CPU_ICON="🖥️"
MEM_ICON="💾"
TIME_ICON="⏱️"
LOG_ICON="📋"

# 获取终端尺寸
get_terminal_size() {
    TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
    TERM_HEIGHT=$(tput lines 2>/dev/null || echo 24)
}

# 绘制分隔线
draw_line() {
    local char=${1:-"="}
    local width=${2:-$TERM_WIDTH}
    printf "%*s\n" "$width" "" | tr ' ' "$char"
}

# 绘制标题
draw_title() {
    local title="$1"
    local title_len=${#title}
    local padding=$(( (TERM_WIDTH - title_len) / 2 ))
    
    echo -e "${CYAN}$(draw_line)${NC}"
    printf "%*s%s%*s\n" "$padding" "" "$title" "$padding" ""
    echo -e "${CYAN}$(draw_line)${NC}"
}

# 获取实例状态
get_instance_status() {
    local instance_id=$1
    local pid_file="$PID_DIR/nexus_$instance_id.pid"
    
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

# 获取进程信息
get_process_info() {
    local pid=$1
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        echo "- - - -"
        return
    fi
    
    # 获取CPU、内存、运行时间
    local ps_output=$(ps -p "$pid" -o pcpu,pmem,etime,command --no-headers 2>/dev/null)
    if [ -n "$ps_output" ]; then
        echo "$ps_output"
    else
        echo "- - - -"
    fi
}

# 获取系统资源使用情况
get_system_resources() {
    # CPU使用率
    local cpu_usage="-"
    if command -v top >/dev/null 2>&1; then
        cpu_usage=$(top -l 1 -n 0 | grep "CPU usage" | awk '{print $3}' | sed 's/%//' 2>/dev/null || echo "-")
    fi
    
    # 内存使用情况
    local mem_info="-"
    if command -v vm_stat >/dev/null 2>&1; then
        local pages_free=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        local pages_active=$(vm_stat | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
        local pages_inactive=$(vm_stat | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
        local pages_speculative=$(vm_stat | grep "Pages speculative" | awk '{print $3}' | sed 's/\.//')
        local pages_wired=$(vm_stat | grep "Pages wired down" | awk '{print $4}' | sed 's/\.//')
        
        if [ -n "$pages_free" ] && [ -n "$pages_active" ]; then
            local total_pages=$((pages_free + pages_active + pages_inactive + pages_speculative + pages_wired))
            local used_pages=$((total_pages - pages_free))
            local mem_percent=$((used_pages * 100 / total_pages))
            mem_info="${mem_percent}%"
        fi
    fi
    
    echo "$cpu_usage $mem_info"
}

# 显示实例详细状态
show_detailed_status() {
    clear
    get_terminal_size
    
    draw_title "${BOLD}${WHITE}NEXUS 多实例监控面板${NC}"
    
    # 系统信息
    local sys_resources=$(get_system_resources)
    local sys_cpu=$(echo "$sys_resources" | awk '{print $1}')
    local sys_mem=$(echo "$sys_resources" | awk '{print $2}')
    
    echo -e "${BLUE}${BOLD}系统状态:${NC} ${CPU_ICON} CPU: ${sys_cpu} | ${MEM_ICON} 内存: ${sys_mem} | ${TIME_ICON} 时间: $(date '+%H:%M:%S')${NC}"
    echo ""
    
    # 实例状态表格
    printf "${CYAN}${BOLD}%-4s %-8s %-8s %-8s %-8s %-12s %-20s${NC}\n" "ID" "状态" "PID" "CPU%" "MEM%" "运行时间" "命令"
    echo -e "${CYAN}$(draw_line "-" 70)${NC}"
    
    local running_count=0
    local total_cpu=0
    local total_mem=0
    
    for i in $(seq 1 $MAX_INSTANCES); do
        local status=$(get_instance_status $i)
        local pid_file="$PID_DIR/nexus_$i.pid"
        local pid="-"
        local cpu="-"
        local mem="-"
        local runtime="-"
        local cmd="-"
        
        if [ "$status" = "RUNNING" ] && [ -f "$pid_file" ]; then
            pid=$(cat "$pid_file")
            local proc_info=$(get_process_info "$pid")
            cpu=$(echo "$proc_info" | awk '{print $1}')
            mem=$(echo "$proc_info" | awk '{print $2}')
            runtime=$(echo "$proc_info" | awk '{print $3}')
            cmd=$(echo "$proc_info" | awk '{for(i=4;i<=NF;i++) printf "%s ", $i; print ""}')
            
            running_count=$((running_count + 1))
            
            # 累计CPU和内存使用
            if [ "$cpu" != "-" ]; then
                total_cpu=$(echo "$total_cpu + $cpu" | bc -l 2>/dev/null || echo "$total_cpu")
            fi
            if [ "$mem" != "-" ]; then
                total_mem=$(echo "$total_mem + $mem" | bc -l 2>/dev/null || echo "$total_mem")
            fi
        fi
        
        # 状态图标和颜色
        local status_display
        case $status in
            "RUNNING") 
                status_display="${GREEN}${RUNNING}运行${NC}"
                ;;
            "STOPPED") 
                status_display="${YELLOW}${STOPPED}停止${NC}"
                ;;
            "DEAD") 
                status_display="${RED}${DEAD}死亡${NC}"
                ;;
        esac
        
        # 截断命令显示
        if [ ${#cmd} -gt 20 ]; then
            cmd="${cmd:0:17}..."
        fi
        
        printf "%-4s %-18s %-8s %-8s %-8s %-12s %-20s\n" "$i" "$status_display" "$pid" "$cpu" "$mem" "$runtime" "$cmd"
    done
    
    echo ""
    echo -e "${GREEN}${BOLD}统计信息:${NC} 运行实例: $running_count/$MAX_INSTANCES | 总CPU使用: ${total_cpu}% | 总内存使用: ${total_mem}%${NC}"
}

# 显示实例日志
show_instance_logs() {
    local instance_id=$1
    local log_file="$LOG_DIR/nexus_$instance_id.log"
    
    if [ ! -f "$log_file" ]; then
        echo -e "${RED}${CROSS_MARK} 实例 $instance_id 的日志文件不存在${NC}"
        return
    fi
    
    echo -e "${CYAN}${BOLD}${LOG_ICON} 实例 $instance_id 日志 (最近 $LOG_LINES 行):${NC}"
    echo -e "${BLUE}$(draw_line "-" 50)${NC}"
    
    # 显示日志，添加时间戳和颜色
    tail -n "$LOG_LINES" "$log_file" | while IFS= read -r line; do
        local timestamp=$(date '+%H:%M:%S')
        
        # 根据日志内容添加颜色
        if echo "$line" | grep -qi "error\|failed\|exception"; then
            echo -e "${RED}[$timestamp] $line${NC}"
        elif echo "$line" | grep -qi "warning\|warn"; then
            echo -e "${YELLOW}[$timestamp] $line${NC}"
        elif echo "$line" | grep -qi "success\|completed\|finished"; then
            echo -e "${GREEN}[$timestamp] $line${NC}"
        else
            echo -e "${WHITE}[$timestamp] $line${NC}"
        fi
    done
}

# 交互式监控模式
interactive_monitor() {
    local selected_instance=1
    local show_logs=false
    
    # 隐藏光标
    tput civis
    
    while true; do
        if [ "$show_logs" = true ]; then
            clear
            draw_title "${BOLD}${WHITE}实例 $selected_instance 日志监控${NC}"
            show_instance_logs "$selected_instance"
            echo ""
            echo -e "${PURPLE}${BOLD}控制: [↑/↓] 切换实例 | [L] 切换日志/状态 | [R] 刷新 | [Q] 退出${NC}"
        else
            show_detailed_status
            echo ""
            echo -e "${PURPLE}${BOLD}控制: [↑/↓] 选择实例 | [L] 查看日志 | [R] 刷新 | [Q] 退出 | 当前选择: 实例 $selected_instance${NC}"
        fi
        
        # 非阻塞读取用户输入
        if read -t "$REFRESH_INTERVAL" -n 1 key 2>/dev/null; then
            case "$key" in
                'q'|'Q')
                    break
                    ;;
                'l'|'L')
                    show_logs=$([ "$show_logs" = true ] && echo false || echo true)
                    ;;
                'r'|'R')
                    # 强制刷新
                    continue
                    ;;
                $'\033')
                    # 读取箭头键序列
                    read -t 0.1 -n 2 arrow 2>/dev/null
                    case "$arrow" in
                        '[A') # 上箭头
                            selected_instance=$((selected_instance > 1 ? selected_instance - 1 : MAX_INSTANCES))
                            ;;
                        '[B') # 下箭头
                            selected_instance=$((selected_instance < MAX_INSTANCES ? selected_instance + 1 : 1))
                            ;;
                    esac
                    ;;
            esac
        fi
    done
    
    # 显示光标
    tput cnorm
}

# 生成性能报告
generate_report() {
    local report_file="$HOME/.nexus/performance_report_$(date +%Y%m%d_%H%M%S).txt"
    
    echo "Nexus 多实例性能报告" > "$report_file"
    echo "生成时间: $(date)" >> "$report_file"
    echo "" >> "$report_file"
    
    # 系统信息
    echo "=== 系统信息 ===" >> "$report_file"
    uname -a >> "$report_file"
    echo "" >> "$report_file"
    
    # 实例状态
    echo "=== 实例状态 ===" >> "$report_file"
    for i in $(seq 1 $MAX_INSTANCES); do
        local status=$(get_instance_status $i)
        local pid_file="$PID_DIR/nexus_$i.pid"
        
        echo "实例 $i: $status" >> "$report_file"
        
        if [ "$status" = "RUNNING" ] && [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file")
            local proc_info=$(get_process_info "$pid")
            echo "  PID: $pid" >> "$report_file"
            echo "  进程信息: $proc_info" >> "$report_file"
        fi
        echo "" >> "$report_file"
    done
    
    echo -e "${GREEN}${CHECK_MARK} 性能报告已生成: $report_file${NC}"
}

# 显示帮助信息
show_help() {
    echo -e "${CYAN}${BOLD}Nexus CLI 高级监控界面${NC}"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -i, --interactive    交互式监控模式 (默认)"
    echo "  -s, --status         显示一次状态后退出"
    echo "  -l, --logs <ID>      显示指定实例的日志"
    echo "  -r, --report         生成性能报告"
    echo "  -h, --help           显示此帮助信息"
    echo ""
    echo "交互式监控控制:"
    echo "  ↑/↓ 箭头键          选择实例"
    echo "  L                    切换日志/状态视图"
    echo "  R                    强制刷新"
    echo "  Q                    退出"
    echo ""
    echo "示例:"
    echo "  $0                   # 启动交互式监控"
    echo "  $0 -s                # 显示一次状态"
    echo "  $0 -l 1              # 显示实例1的日志"
    echo "  $0 -r                # 生成性能报告"
}

# 主函数
main() {
    # 检查必要目录
    if [ ! -d "$PID_DIR" ] || [ ! -d "$LOG_DIR" ]; then
        echo -e "${RED}${CROSS_MARK} 错误: 监控目录不存在，请先运行主脚本初始化${NC}"
        exit 1
    fi
    
    case "${1:-interactive}" in
        "-i"|"--interactive"|"interactive")
            interactive_monitor
            ;;
        "-s"|"--status"|"status")
            show_detailed_status
            ;;
        "-l"|"--logs"|"logs")
            if [ -z "$2" ]; then
                echo -e "${RED}${CROSS_MARK} 错误: 请指定实例ID${NC}"
                show_help
                exit 1
            fi
            show_instance_logs "$2"
            ;;
        "-r"|"--report"|"report")
            generate_report
            ;;
        "-h"|"--help"|"help")
            show_help
            ;;
        *)
            echo -e "${RED}${CROSS_MARK} 错误: 未知选项 '$1'${NC}"
            show_help
            exit 1
            ;;
    esac
}

# 捕获退出信号
trap 'tput cnorm; echo -e "\n${YELLOW}${INFO} 监控已退出${NC}"; exit 0' INT TERM

# 运行主函数
main "$@"