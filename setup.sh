#!/bin/bash

# Nexus CLI 多开环境安装配置脚本
# 自动编译、配置和初始化多开环境

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# Unicode图标
CHECK_MARK="✅"
CROSS_MARK="❌"
WARNING="⚠️"
INFO="ℹ️"
ROCKET="🚀"
GEAR="⚙️"
FOLDER="📁"
HAMMER="🔨"

# 配置参数
PROJECT_DIR="$(pwd)"
CLI_DIR="$PROJECT_DIR/clients/cli"
SCRIPT_DIR="$PROJECT_DIR"
CONFIG_BASE_DIR="$HOME/.nexus"

# 打印带样式的消息
print_message() {
    local type="$1"
    local message="$2"
    
    case "$type" in
        "info")
            echo -e "${BLUE}${INFO} ${message}${NC}"
            ;;
        "success")
            echo -e "${GREEN}${CHECK_MARK} ${message}${NC}"
            ;;
        "warning")
            echo -e "${YELLOW}${WARNING} ${message}${NC}"
            ;;
        "error")
            echo -e "${RED}${CROSS_MARK} ${message}${NC}"
            ;;
        "step")
            echo -e "${CYAN}${GEAR} ${message}${NC}"
            ;;
    esac
}

# 打印标题
print_title() {
    local title="$1"
    echo ""
    echo -e "${CYAN}${BOLD}================================${NC}"
    echo -e "${WHITE}${BOLD}  $title${NC}"
    echo -e "${CYAN}${BOLD}================================${NC}"
    echo ""
}

# 检查系统要求
check_requirements() {
    print_title "检查系统要求"
    
    # 检查操作系统
    if [[ "$OSTYPE" == "darwin"* ]]; then
        print_success "检测到 macOS 系统"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        print_success "检测到 Linux 系统"
    else
        print_warning "未知操作系统: $OSTYPE"
    fi
    
    # 检查Rust
    if command -v rustc >/dev/null 2>&1; then
        local rust_version=$(rustc --version)
        print_success "Rust 已安装: $rust_version"
    else
        print_error "Rust 未安装，请先安装 Rust: https://rustup.rs/"
        return 1
    fi
    
    # 检查Cargo
    if command -v cargo >/dev/null 2>&1; then
        local cargo_version=$(cargo --version)
        print_success "Cargo 已安装: $cargo_version"
    else
        print_error "Cargo 未安装"
        return 1
    fi
    
    # 检查Git
    if command -v git >/dev/null 2>&1; then
        print_success "Git 已安装"
    else
        print_warning "Git 未安装，某些功能可能受限"
    fi
    
    # 检查必要的命令行工具
    local tools=("ps" "kill" "tail" "head" "grep" "awk" "sed")
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            print_success "$tool 可用"
        else
            print_error "$tool 不可用，请安装"
            return 1
        fi
    done
    
    return 0
}

# 编译Nexus CLI
compile_nexus_cli() {
    print_title "编译 Nexus CLI"
    
    if [ ! -d "$CLI_DIR" ]; then
        print_error "CLI 目录不存在: $CLI_DIR"
        return 1
    fi
    
    cd "$CLI_DIR" || return 1
    
    print_step "清理之前的编译..."
    cargo clean
    
    print_step "开始编译 (Release 模式)..."
    if cargo build --release; then
        print_success "Nexus CLI 编译成功"
        
        # 检查可执行文件
        local binary_path="$CLI_DIR/target/release/nexus-network"
        if [ -f "$binary_path" ]; then
            print_success "可执行文件位置: $binary_path"
            
            # 显示文件信息
            local file_size=$(ls -lh "$binary_path" | awk '{print $5}')
            print_info "文件大小: $file_size"
        else
            print_error "可执行文件未找到"
            return 1
        fi
    else
        print_error "编译失败"
        return 1
    fi
    
    cd "$PROJECT_DIR" || return 1
    return 0
}

# 创建配置目录结构
setup_directories() {
    print_title "创建配置目录"
    
    local dirs=(
        "$CONFIG_BASE_DIR"
        "$CONFIG_BASE_DIR/logs"
        "$CONFIG_BASE_DIR/pids"
        "$CONFIG_BASE_DIR/instances"
        "$CONFIG_BASE_DIR/backups"
    )
    
    for dir in "${dirs[@]}"; do
        if mkdir -p "$dir"; then
            print_success "创建目录: $dir"
        else
            print_error "创建目录失败: $dir"
            return 1
        fi
    done
    
    return 0
}

# 设置脚本权限
setup_scripts() {
    print_title "配置脚本权限"
    
    local scripts=(
        "$SCRIPT_DIR/nexus_multi_runner.sh"
        "$SCRIPT_DIR/nexus_monitor.sh"
        "$SCRIPT_DIR/setup.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            if chmod +x "$script"; then
                print_success "设置执行权限: $(basename "$script")"
            else
                print_error "设置权限失败: $script"
                return 1
            fi
        else
            print_warning "脚本不存在: $script"
        fi
    done
    
    return 0
}

# 创建快捷启动脚本
create_shortcuts() {
    print_title "创建快捷启动脚本"
    
    # 创建主启动脚本的软链接
    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"
    
    # nexus-multi 命令
    local nexus_multi_link="$bin_dir/nexus-multi"
    if ln -sf "$SCRIPT_DIR/nexus_multi_runner.sh" "$nexus_multi_link"; then
        print_success "创建快捷命令: nexus-multi"
    else
        print_warning "创建 nexus-multi 快捷命令失败"
    fi
    
    # nexus-monitor 命令
    local nexus_monitor_link="$bin_dir/nexus-monitor"
    if ln -sf "$SCRIPT_DIR/nexus_monitor.sh" "$nexus_monitor_link"; then
        print_success "创建快捷命令: nexus-monitor"
    else
        print_warning "创建 nexus-monitor 快捷命令失败"
    fi
    
    # 检查PATH
    if echo "$PATH" | grep -q "$bin_dir"; then
        print_success "$bin_dir 已在 PATH 中"
    else
        print_warning "$bin_dir 不在 PATH 中"
        print_info "请将以下行添加到您的 shell 配置文件 (~/.bashrc, ~/.zshrc 等):"
        echo -e "${YELLOW}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
    fi
}

# 创建示例配置文件
create_example_configs() {
    print_title "创建示例配置文件"
    
    # 创建示例配置
    local example_config="$CONFIG_BASE_DIR/example_config.json"
    cat > "$example_config" << 'EOF'
{
  "environment": "production",
  "user_id": "your-user-id-here",
  "wallet_address": "0x1234567890123456789012345678901234567890",
  "node_id": "123456"
}
EOF
    
    if [ -f "$example_config" ]; then
        print_success "创建示例配置: $example_config"
    else
        print_error "创建示例配置失败"
    fi
    
    # 创建启动配置模板
    local startup_template="$CONFIG_BASE_DIR/startup_template.sh"
    cat > "$startup_template" << 'EOF'
#!/bin/bash
# Nexus 多开启动模板
# 根据需要修改以下参数

# 启动实例数量
INSTANCE_COUNT=5

# 每个实例的线程数
THREADS_PER_INSTANCE=2

# 节点ID列表 (可选，如果为空则匿名运行)
NODE_IDS=(
    # "123456"
    # "123457"
    # "123458"
)

# 启动脚本路径
SCRIPT_PATH="$(dirname "$0")/nexus_multi_runner.sh"

# 批量启动
echo "启动 $INSTANCE_COUNT 个实例..."
"$SCRIPT_PATH" batch-start "$INSTANCE_COUNT" "$THREADS_PER_INSTANCE"

# 等待一段时间后显示状态
sleep 5
"$SCRIPT_PATH" status

echo "启动完成！使用 'nexus-monitor' 查看实时监控"
EOF
    
    chmod +x "$startup_template"
    
    if [ -f "$startup_template" ]; then
        print_success "创建启动模板: $startup_template"
    else
        print_error "创建启动模板失败"
    fi
}

# 运行测试
run_tests() {
    print_title "运行测试"
    
    # 测试编译的二进制文件
    local binary_path="$CLI_DIR/target/release/nexus-network"
    if [ -f "$binary_path" ]; then
        print_step "测试 Nexus CLI 二进制文件..."
        if "$binary_path" --help >/dev/null 2>&1; then
            print_success "Nexus CLI 二进制文件正常工作"
        else
            print_error "Nexus CLI 二进制文件测试失败"
            return 1
        fi
    else
        print_error "二进制文件不存在"
        return 1
    fi
    
    # 测试脚本
    print_step "测试多开脚本..."
    if "$SCRIPT_DIR/nexus_multi_runner.sh" help >/dev/null 2>&1; then
        print_success "多开脚本正常工作"
    else
        print_error "多开脚本测试失败"
        return 1
    fi
    
    print_step "测试监控脚本..."
    if "$SCRIPT_DIR/nexus_monitor.sh" --help >/dev/null 2>&1; then
        print_success "监控脚本正常工作"
    else
        print_error "监控脚本测试失败"
        return 1
    fi
    
    return 0
}

# 显示安装完成信息
show_completion_info() {
    print_title "安装完成"
    
    echo -e "${GREEN}${ROCKET} Nexus CLI 多开环境安装成功！${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}可用命令:${NC}"
    echo -e "  ${WHITE}nexus-multi${NC}     - 多实例管理 (如果已添加到PATH)"
    echo -e "  ${WHITE}nexus-monitor${NC}   - 实时监控界面 (如果已添加到PATH)"
    echo ""
    echo -e "${CYAN}${BOLD}或者直接使用:${NC}"
    echo -e "  ${WHITE}./nexus_multi_runner.sh${NC}  - 多实例管理"
    echo -e "  ${WHITE}./nexus_monitor.sh${NC}       - 实时监控界面"
    echo ""
    echo -e "${CYAN}${BOLD}快速开始:${NC}"
    echo -e "  ${YELLOW}1.${NC} 启动5个实例: ${WHITE}./nexus_multi_runner.sh batch-start 5 2${NC}"
    echo -e "  ${YELLOW}2.${NC} 查看状态: ${WHITE}./nexus_multi_runner.sh status${NC}"
    echo -e "  ${YELLOW}3.${NC} 实时监控: ${WHITE}./nexus_monitor.sh${NC}"
    echo -e "  ${YELLOW}4.${NC} 停止所有: ${WHITE}./nexus_multi_runner.sh batch-stop${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}配置文件位置:${NC}"
    echo -e "  ${WHITE}配置目录:${NC} $CONFIG_BASE_DIR"
    echo -e "  ${WHITE}日志目录:${NC} $CONFIG_BASE_DIR/logs"
    echo -e "  ${WHITE}示例配置:${NC} $CONFIG_BASE_DIR/example_config.json"
    echo -e "  ${WHITE}启动模板:${NC} $CONFIG_BASE_DIR/startup_template.sh"
    echo ""
    echo -e "${GREEN}${BOLD}享受挖矿！${NC} ${ROCKET}"
}

# 清理函数
cleanup() {
    print_title "清理安装文件"
    
    # 清理编译缓存
    if [ -d "$CLI_DIR/target" ]; then
        print_step "清理编译缓存..."
        cd "$CLI_DIR" && cargo clean
        print_success "编译缓存已清理"
    fi
    
    cd "$PROJECT_DIR"
}

# 卸载函数
uninstall() {
    print_title "卸载 Nexus 多开环境"
    
    read -p "确定要卸载吗？这将删除所有配置和日志 (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # 停止所有实例
        if [ -f "$SCRIPT_DIR/nexus_multi_runner.sh" ]; then
            print_step "停止所有运行中的实例..."
            "$SCRIPT_DIR/nexus_multi_runner.sh" batch-stop
        fi
        
        # 删除配置目录
        if [ -d "$CONFIG_BASE_DIR" ]; then
            print_step "删除配置目录..."
            rm -rf "$CONFIG_BASE_DIR"
            print_success "配置目录已删除"
        fi
        
        # 删除快捷命令
        local bin_dir="$HOME/.local/bin"
        for cmd in "nexus-multi" "nexus-monitor"; do
            if [ -L "$bin_dir/$cmd" ]; then
                rm -f "$bin_dir/$cmd"
                print_success "删除快捷命令: $cmd"
            fi
        done
        
        print_success "卸载完成"
    else
        print_info "取消卸载"
    fi
}

# 显示帮助信息
show_help() {
    echo -e "${CYAN}${BOLD}Nexus CLI 多开环境安装脚本${NC}"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  install     完整安装 (默认)"
    echo "  compile     仅编译 Nexus CLI"
    echo "  setup       仅设置环境 (不编译)"
    echo "  test        运行测试"
    echo "  clean       清理编译文件"
    echo "  uninstall   卸载环境"
    echo "  help        显示此帮助"
    echo ""
    echo "示例:"
    echo "  $0 install   # 完整安装"
    echo "  $0 compile   # 仅编译"
    echo "  $0 test      # 测试安装"
}

# 主安装函数
install_all() {
    print_title "${ROCKET} Nexus CLI 多开环境安装"
    
    # 检查系统要求
    if ! check_requirements; then
        print_error "系统要求检查失败"
        exit 1
    fi
    
    # 编译 Nexus CLI
    if ! compile_nexus_cli; then
        print_error "编译失败"
        exit 1
    fi
    
    # 设置目录
    if ! setup_directories; then
        print_error "目录设置失败"
        exit 1
    fi
    
    # 设置脚本权限
    if ! setup_scripts; then
        print_error "脚本设置失败"
        exit 1
    fi
    
    # 创建快捷命令
    create_shortcuts
    
    # 创建示例配置
    create_example_configs
    
    # 运行测试
    if ! run_tests; then
        print_error "测试失败"
        exit 1
    fi
    
    # 显示完成信息
    show_completion_info
}

# 主函数
main() {
    case "${1:-install}" in
        "install")
            install_all
            ;;
        "compile")
            check_requirements && compile_nexus_cli
            ;;
        "setup")
            setup_directories && setup_scripts && create_shortcuts && create_example_configs
            ;;
        "test")
            run_tests
            ;;
        "clean")
            cleanup
            ;;
        "uninstall")
            uninstall
            ;;
        "help")
            show_help
            ;;
        *)
            print_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 捕获中断信号
trap 'echo -e "\n${YELLOW}${WARNING} 安装被中断${NC}"; exit 1' INT

# 运行主函数
main "$@"