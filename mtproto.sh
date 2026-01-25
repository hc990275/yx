#!/bin/bash

# =========================================================
# 脚本名称: MTProto Proxy + Cloudflare Tunnel 一键管理脚本
# 功能描述: 安装 MTG 代理，配置 Cloudflare Tunnel，支持快捷键管理
# 系统要求: Ubuntu / Debian / CentOS (推荐 Ubuntu 20.04+)
# =========================================================

# --- 全局变量定义 ---
MTG_BIN="/usr/local/bin/mtg"
MTG_SERVICE="/etc/systemd/system/mtg.service"
CF_BIN="/usr/local/bin/cloudflared"
SHORTCUT_BIN="/usr/local/bin/m"

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[36m'
PLAIN='\033[0m'

# --- 辅助函数 ---

# 检查是否为 Root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 请使用 root 用户运行此脚本！${PLAIN}"
        exit 1
    fi
}

# 检查系统类型并安装依赖
install_dependencies() {
    echo -e "${YELLOW}正在检查并安装系统依赖...${PLAIN}"
    if [ -f /etc/debian_version ]; then
        apt-get update -y
        apt-get install -y curl wget tar jq
    elif [ -f /etc/redhat-release ]; then
        yum install -y curl wget tar jq
    else
        echo -e "${RED}不支持的操作系统！${PLAIN}"
        exit 1
    fi
}

# 创建快捷键 m
create_shortcut() {
    cp "$0" "$SHORTCUT_BIN"
    chmod +x "$SHORTCUT_BIN"
    echo -e "${GREEN}快捷键 'm' 创建成功！以后输入 m 即可管理服务。${PLAIN}"
}

# --- MTProto (MTG) 相关函数 ---

# 获取最新版 MTG 下载链接
get_mtg_url() {
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  FILE_ARCH="amd64" ;;
        aarch64) FILE_ARCH="arm64" ;;
        *)       echo -e "${RED}不支持的架构: $ARCH${PLAIN}"; return 1 ;;
    esac

    # 这里使用 9seconds/mtg 的稳定版本
    echo "https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-linux-${FILE_ARCH}.tar.gz"
}

# 安装 MTProto
install_mtproto() {
    echo -e "${BLUE}=== 开始安装 MTProto 代理 ===${PLAIN}"
    
    # 1. 下载
    DOWNLOAD_URL=$(get_mtg_url)
    echo -e "正在下载 MTG: ${DOWNLOAD_URL}"
    wget -O mtg.tar.gz "$DOWNLOAD_URL"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载失败，请检查网络连接。${PLAIN}"
        rm mtg.tar.gz
        return
    fi

    # 2. 解压安装
    mkdir -p mtg_temp
    tar -xzf mtg.tar.gz -C mtg_temp --strip-components=1
    mv mtg_temp/mtg "$MTG_BIN"
    chmod +x "$MTG_BIN"
    rm -rf mtg.tar.gz mtg_temp
    
    echo -e "${GREEN}MTG 二进制文件安装完毕。${PLAIN}"

    # 3. 配置参数
    echo -e "${YELLOW}请配置 MTProto 代理参数:${PLAIN}"
    
    read -p "请输入监听端口 (默认 443, 回车使用默认): " MTG_PORT
    [[ -z "$MTG_PORT" ]] && MTG_PORT=443
    
    read -p "请输入伪装域名 (用于 TLS 伪装, 默认 google.com): " MTG_DOMAIN
    [[ -z "$MTG_DOMAIN" ]] && MTG_DOMAIN="google.com"

    # 生成密钥
    SECRET=$($MTG_BIN generate-secret --hex "$MTG_DOMAIN")
    echo -e "${GREEN}已生成密钥: $SECRET${PLAIN}"

    # 4. 创建 Systemd 服务
    cat > "$MTG_SERVICE" <<EOF
[Unit]
Description=MTG Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=$MTG_BIN simple-run -b 0.0.0.0:$MTG_PORT $SECRET
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    # 5. 启动服务
    systemctl daemon-reload
    systemctl enable mtg
    systemctl start mtg
    
    echo -e "${GREEN}MTProto 代理已启动！${PLAIN}"
    echo -e "本地监听端口: ${MTG_PORT}"
    echo -e "专用密钥 (Secret): ${SECRET}"
    
    # 保存配置信息到本地文件以便查看
    echo "PORT=$MTG_PORT" > /etc/mtg_info
    echo "SECRET=$SECRET" >> /etc/mtg_info
    echo "DOMAIN=$MTG_DOMAIN" >> /etc/mtg_info
}

# --- Cloudflare Tunnel 相关函数 ---

install_cloudflared() {
    echo -e "${BLUE}=== 开始安装 Cloudflare Tunnel ===${PLAIN}"
    
    # 1. 获取 Token
    echo -e "${YELLOW}请务必确保你在 Cloudflare Zero Trust 面板已经创建了 Tunnel 并获得了 Token。${PLAIN}"
    read -p "请输入 Cloudflare Tunnel Token: " CF_TOKEN
    
    if [[ -z "$CF_TOKEN" ]]; then
        echo -e "${RED}Token 不能为空！取消安装 Tunnel。${PLAIN}"
        return
    fi

    # 2. 下载安装 Cloudflared
    echo -e "正在下载 Cloudflared..."
    if [ -f /etc/debian_version ]; then
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        dpkg -i cloudflared-linux-amd64.deb
        rm cloudflared-linux-amd64.deb
    elif [ -f /etc/redhat-release ]; then
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-x86_64.rpm
        rpm -ivh cloudflared-linux-x86_64.rpm
        rm cloudflared-linux-x86_64.rpm
    fi

    # 3. 注册服务
    cloudflared service uninstall 2>/dev/null
    cloudflared service install "$CF_TOKEN"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Cloudflare Tunnel 安装并注册成功！${PLAIN}"
    else
        echo -e "${RED}Cloudflare Tunnel 注册失败，请检查 Token 是否正确。${PLAIN}"
    fi
}

# --- 管理功能函数 ---

start_services() {
    systemctl start mtg
    systemctl start cloudflared
    echo -e "${GREEN}所有服务已发送启动命令。${PLAIN}"
}

stop_services() {
    systemctl stop mtg
    systemctl stop cloudflared
    echo -e "${RED}所有服务已停止。${PLAIN}"
}

restart_services() {
    systemctl restart mtg
    systemctl restart cloudflared
    echo -e "${GREEN}所有服务已重启。${PLAIN}"
}

view_logs() {
    echo -e "${YELLOW}请选择要查看的日志:${PLAIN}"
    echo "1. MTProto 代理日志"
    echo "2. Cloudflare Tunnel 日志"
    read -p "请输入数字: " LOG_CHOICE
    
    if [[ "$LOG_CHOICE" == "1" ]]; then
        journalctl -u mtg -f
    elif [[ "$LOG_CHOICE" == "2" ]]; then
        journalctl -u cloudflared -f
    else
        echo -e "${RED}输入错误。${PLAIN}"
    fi
}

show_status() {
    echo -e "${BLUE}=== 服务运行状态 ===${PLAIN}"
    echo -n "MTProto 状态: "
    if systemctl is-active --quiet mtg; then echo -e "${GREEN}运行中${PLAIN}"; else echo -e "${RED}未运行${PLAIN}"; fi
    
    echo -n "Tunnel  状态: "
    if systemctl is-active --quiet cloudflared; then echo -e "${GREEN}运行中${PLAIN}"; else echo -e "${RED}未运行${PLAIN}"; fi
    
    if [ -f /etc/mtg_info ]; then
        echo -e "\n${BLUE}=== MTProto 配置信息 ===${PLAIN}"
        source /etc/mtg_info
        echo -e "本地端口: $PORT"
        echo -e "密钥 (Secret): $SECRET"
        echo -e "伪装域名: $DOMAIN"
        echo -e "${YELLOW}注意: 如果使用 Cloudflare Tunnel，请在 CF 后台将 Tunnel 指向 localhost:$PORT${PLAIN}"
    fi
}

uninstall_all() {
    read -p "确定要卸载所有服务吗？(y/n): " CONFIRM
    if [[ "$CONFIRM" == "y" ]]; then
        systemctl stop mtg
        systemctl disable mtg
        rm "$MTG_BIN"
        rm "$MTG_SERVICE"
        rm /etc/mtg_info
        
        cloudflared service uninstall
        apt-get remove -y cloudflared 2>/dev/null
        yum remove -y cloudflared 2>/dev/null
        
        echo -e "${GREEN}所有服务已卸载。${PLAIN}"
    else
        echo -e "操作取消。"
    fi
}

# --- 主菜单 ---

menu() {
    clear
    echo -e "${BLUE}=========================================${PLAIN}"
    echo -e "${BLUE}    MTProto + Cloudflare Tunnel 管理脚本   ${PLAIN}"
    echo -e "${BLUE}=========================================${PLAIN}"
    echo -e "1. 安装所有服务 (MTProto + Tunnel)"
    echo -e "2. 单独修改/重装 Cloudflare Token"
    echo -e "3. 启动所有服务"
    echo -e "4. 停止所有服务"
    echo -e "5. 重启所有服务"
    echo -e "6. 查看服务状态 & 连接信息"
    echo -e "7. 查看日志"
    echo -e "8. 卸载所有服务"
    echo -e "0. 退出脚本"
    echo -e "${BLUE}=========================================${PLAIN}"
    read -p "请输入数字 [0-8]: " choice

    case $choice in
        1)
            install_dependencies
            install_mtproto
            install_cloudflared
            create_shortcut
            show_status
            ;;
        2)
            install_cloudflared
            ;;
        3)
            start_services
            ;;
        4)
            stop_services
            ;;
        5)
            restart_services
            ;;
        6)
            show_status
            ;;
        7)
            view_logs
            ;;
        8)
            uninstall_all
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RED}无效输入，请重新输入。${PLAIN}"
            sleep 1
            menu
            ;;
    esac
}

# --- 脚本入口 ---

check_root
# 如果有参数传入 (例如快捷键调用)，这里可以处理，目前默认直接进菜单
menu
