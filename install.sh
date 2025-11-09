#!/bin/bash
# Komari Monitor RS 一键安装/卸载脚本
# 适用于 Debian/Ubuntu (systemd) 和 Alpine (OpenRC) 系统
# 适用于x86_64架构的Linux系统

set -e  # 遇到错误时退出

# 全局变量
HTTP_SERVER=""
WS_SERVER=""
TOKEN=""
INSTALL_DIR="/opt/komari"
DOWNLOAD_URL=""
INIT_SYSTEM=""
LIBC_TYPE=""
ACTION=""

# 函数: 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "错误: 请以 root 权限运行此脚本"
        echo "使用: sudo bash install.sh"
        exit 1
    fi
}

# 函数: 选择操作
select_action() {
    echo "请选择操作："
    echo "  1) 安装 Komari Monitor RS"
    echo "  2) 卸载 Komari Monitor RS"
    echo ""
    read -p "请输入选项 [1-2]: " choice
    
    case $choice in
        1)
            ACTION="install"
            ;;
        2)
            ACTION="uninstall"
            ;;
        *)
            echo "错误: 无效的选项"
            exit 1
            ;;
    esac
}

# 函数: 检测初始化系统
detect_init_system() {
    if command -v systemctl &> /dev/null && systemctl &> /dev/null; then
        INIT_SYSTEM="systemd"
        echo "检测到初始化系统: systemd (Debian/Ubuntu/CentOS 7+)"
    elif command -v rc-service &> /dev/null; then
        INIT_SYSTEM="openrc"
        echo "检测到初始化系统: OpenRC (Alpine)"
    else
        echo "错误: 无法检测到支持的初始化系统 (systemd 或 OpenRC)"
        exit 1
    fi
}

# 函数: 检测 C 库类型
detect_libc() {
    if ldd --version 2>&1 | grep -q musl; then
        LIBC_TYPE="musl"
        DOWNLOAD_URL="https://github.com/GenshinMinecraft/komari-monitor-rs/releases/download/latest/komari-monitor-rs-linux-x86_64-musl"
        echo "检测到 C 库类型: musl"
    elif ldd --version 2>&1 | grep -q GLIBC; then
        LIBC_TYPE="gnu"
        DOWNLOAD_URL="https://github.com/GenshinMinecraft/komari-monitor-rs/releases/download/latest/komari-monitor-rs-linux-x86_64-gnu"
        echo "检测到 C 库类型: GNU libc (glibc)"
    else
        # 尝试其他方法检测
        if [ -f /lib/ld-musl-x86_64.so.1 ]; then
            LIBC_TYPE="musl"
            DOWNLOAD_URL="https://github.com/GenshinMinecraft/komari-monitor-rs/releases/download/latest/komari-monitor-rs-linux-x86_64-musl"
            echo "检测到 C 库类型: musl"
        else
            LIBC_TYPE="gnu"
            DOWNLOAD_URL="https://github.com/GenshinMinecraft/komari-monitor-rs/releases/download/latest/komari-monitor-rs-linux-x86_64-gnu"
            echo "检测到 C 库类型: GNU libc (glibc) [默认]"
        fi
    fi
}

# ============ 卸载相关函数 ============

# 函数: 停止并禁用服务
stop_and_disable_service() {
    echo "步骤 1/3: 停止并禁用服务..."
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        if systemctl is-active --quiet komari-agent-rs; then
            systemctl stop komari-agent-rs
            echo "✓ 服务已停止 (systemd)"
        fi
        if systemctl is-enabled --quiet komari-agent-rs; then
            systemctl disable komari-agent-rs
            echo "✓ 服务已禁用 (systemd)"
        fi
        
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        if rc-service komari-agent-rs status &> /dev/null; then
            rc-service komari-agent-rs stop || true
            echo "✓ 服务已停止 (OpenRC)"
        fi
        if rc-update show default | grep -q komari-agent-rs; then
            rc-update del komari-agent-rs default
            echo "✓ 服务已禁用 (OpenRC)"
        fi
    fi
}

# 函数: 删除服务文件
remove_service_file() {
    echo "步骤 2/3: 删除服务文件..."
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        if [ -f /etc/systemd/system/komari-agent-rs.service ]; then
            rm -f /etc/systemd/system/komari-agent-rs.service
            systemctl daemon-reload
            echo "✓ systemd 服务文件已删除"
        fi
        
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        if [ -f /etc/init.d/komari-agent-rs ]; then
            rm -f /etc/init.d/komari-agent-rs
            echo "✓ OpenRC 服务文件已删除"
        fi
    fi
}

# 函数: 删除程序文件
remove_program_files() {
    echo "步骤 3/3: 删除程序文件..."
    
    if [ -d "${INSTALL_DIR}" ]; then
        rm -rf "${INSTALL_DIR}"
        echo "✓ 程序文件已删除: ${INSTALL_DIR}"
    else
        echo "✓ 程序目录不存在，跳过"
    fi
}

# 函数: 显示卸载完成信息
show_uninstall_completion() {
    echo ""
    echo "=== 卸载完成！==="
    echo ""
    echo "Komari Monitor RS 已完全从系统中移除。"
    echo ""
}

# 函数: 执行卸载流程
uninstall_process() {
    echo "=== 开始卸载 Komari Monitor RS ==="
    echo ""
    
    read -p "确认要卸载 Komari Monitor RS 吗? [y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "卸载已取消"
        exit 0
    fi
    
    echo ""
    
    # 检测初始化系统
    detect_init_system
    echo ""
    
    # 执行卸载步骤
    stop_and_disable_service
    remove_service_file
    remove_program_files
    
    # 显示完成信息
    show_uninstall_completion
}

# ============ 安装相关函数 ============

# 函数: 交互式输入配置
input_config() {
    echo "=== Komari Monitor RS 配置 ==="
    echo ""
    
    # 输入 HTTP 服务器地址
    while [ -z "$HTTP_SERVER" ]; do
        read -p "请输入 HTTP 服务器地址 (例如: https://example.com:443): " input_http
        HTTP_SERVER="$input_http"
        if [ -z "$HTTP_SERVER" ]; then
            echo "错误: HTTP 服务器地址不能为空，请重新输入"
        fi
    done
    
    # 输入 WebSocket 服务器地址
    while [ -z "$WS_SERVER" ]; do
        read -p "请输入 WebSocket 服务器地址 (例如: wss://example.com:443): " input_ws
        WS_SERVER="$input_ws"
        if [ -z "$WS_SERVER" ]; then
            echo "错误: WebSocket 服务器地址不能为空，请重新输入"
        fi
    done
    
    # 输入 Token
    while [ -z "$TOKEN" ]; do
        read -p "请输入认证 Token: " input_token
        TOKEN="$input_token"
        if [ -z "$TOKEN" ]; then
            echo "错误: Token 不能为空，请重新输入"
        fi
    done
    
    echo ""
    echo "=== 配置确认 ==="
    echo "HTTP 服务器: ${HTTP_SERVER}"
    echo "WebSocket 服务器: ${WS_SERVER}"
    echo "Token: ${TOKEN}"
    echo ""
    read -p "确认以上配置并继续安装? [Y/n]: " confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]] && [[ ! -z $confirm ]]; then
        echo "安装已取消"
        exit 0
    fi
}

# 函数: 创建安装目录
create_directory() {
    echo "步骤 1/6: 创建安装目录..."
    mkdir -p ${INSTALL_DIR}
    cd ${INSTALL_DIR}
    echo "✓ 目录创建完成: ${INSTALL_DIR}"
}

# 函数: 下载程序
download_program() {
    echo "步骤 2/6: 下载 komari-agent-rs..."
    wget -O ./komari-agent-rs ${DOWNLOAD_URL}
    echo "✓ 下载完成"
}

# 函数: 赋予执行权限
set_permissions() {
    echo "步骤 3/6: 赋予执行权限..."
    chmod +x ./komari-agent-rs
    echo "✓ 权限设置完成"
}

# 函数: 测试运行
test_run() {
    echo "步骤 4/6: 测试运行程序 (5秒后自动停止)..."
    timeout 5 ./komari-agent-rs --http-server "${HTTP_SERVER}" --ws-server "${WS_SERVER}" -t "${TOKEN}" || true
    echo "✓ 测试完成"
}

# 函数: 创建系统服务
create_service() {
    echo "步骤 5/6: 创建系统服务..."
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        # 创建 systemd 服务文件
        cat > /etc/systemd/system/komari-agent-rs.service << EOF
[Unit]
Description=Komari Monitoring Agent Service
After=network.target

[Service]
Type=simple
ExecStart=/opt/komari/komari-agent-rs --http-server '${HTTP_SERVER}' --ws-server '${WS_SERVER}' -t '${TOKEN}'
Restart=always
RestartSec=5
User=root
WorkingDirectory=/opt/komari

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        echo "✓ systemd 服务文件创建完成"
        
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        # 创建 OpenRC 服务文件
        cat > /etc/init.d/komari-agent-rs << EOF
#!/sbin/openrc-run

name="komari-agent-rs"
description="Komari Monitoring Agent Service"
command="/opt/komari/komari-agent-rs"
command_args="--http-server '${HTTP_SERVER}' --ws-server '${WS_SERVER}' -t '${TOKEN}'"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"

depend() {
    need net
}

start_pre() {
    checkpath --directory --mode 0755 /run
}
EOF
        chmod +x /etc/init.d/komari-agent-rs
        echo "✓ OpenRC 服务文件创建完成"
    fi
}

# 函数: 启用服务
enable_service() {
    echo "步骤 6/6: 配置服务自启动并启动服务..."
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl enable komari-agent-rs
        systemctl start komari-agent-rs
        echo "✓ 服务已启动 (systemd)"
        
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        rc-update add komari-agent-rs default
        rc-service komari-agent-rs start
        echo "✓ 服务已启动 (OpenRC)"
    fi
}

# 函数: 显示完成信息
show_completion() {
    echo ""
    echo "=== 安装完成！==="
    echo ""
    echo "系统信息："
    echo "  初始化系统: ${INIT_SYSTEM}"
    echo "  C 库类型: ${LIBC_TYPE}"
    echo "  下载链接: ${DOWNLOAD_URL}"
    echo ""
    echo "配置信息："
    echo "  HTTP 服务器: ${HTTP_SERVER}"
    echo "  WebSocket 服务器: ${WS_SERVER}"
    echo "  Token: ${TOKEN}"
    echo ""
    echo "服务状态："
    
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl status komari-agent-rs --no-pager || true
        echo ""
        echo "常用命令 (systemd):"
        echo "  启动服务: systemctl start komari-agent-rs"
        echo "  停止服务: systemctl stop komari-agent-rs"
        echo "  重启服务: systemctl restart komari-agent-rs"
        echo "  查看状态: systemctl status komari-agent-rs"
        echo "  查看日志: journalctl -u komari-agent-rs -f"
        
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        rc-service komari-agent-rs status || true
        echo ""
        echo "常用命令 (OpenRC):"
        echo "  启动服务: rc-service komari-agent-rs start"
        echo "  停止服务: rc-service komari-agent-rs stop"
        echo "  重启服务: rc-service komari-agent-rs restart"
        echo "  查看状态: rc-service komari-agent-rs status"
        echo "  查看日志: tail -f /var/log/messages"
    fi
}

# 函数: 执行安装流程
install_process() {
    echo "=== 开始安装 Komari Monitor RS ==="
    echo ""
    
    # 检测初始化系统
    detect_init_system
    
    # 检测 C 库类型
    detect_libc
    echo ""
    
    # 交互式输入配置
    input_config
    
    echo ""
    echo "=== 开始安装 ==="
    echo ""
    
    # 执行安装步骤
    create_directory
    download_program
    set_permissions
    test_run
    create_service
    enable_service
    
    # 显示完成信息
    show_completion
}

# 主函数
main() {
    echo "=== Komari Monitor RS 一键安装/卸载脚本 ==="
    echo ""
    
    # 检查权限
    check_root
    
    # 选择操作
    select_action
    echo ""
    
    # 根据选择执行相应操作
    if [ "$ACTION" = "install" ]; then
        install_process
    elif [ "$ACTION" = "uninstall" ]; then
        uninstall_process
    fi
}

# 运行主函数
main
