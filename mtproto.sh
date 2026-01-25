#!/bin/bash

# ====================================================
# MTProto & Cloudflare Tunnel 一键管理脚本
# ====================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 工作目录
WORK_DIR="/etc/mtp_proxy"
MTG_BIN="/usr/local/bin/mtg"
TUNNEL_BIN="/usr/local/bin/cloudflared"

# 检查权限
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：请使用 root 权限运行此脚本！${PLAIN}" && exit 1

# 初始化目录
mkdir -p ${WORK_DIR}

# --- 核心功能函数 ---

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}正在安装必要依赖...${PLAIN}"
    apt-get update && apt-get install -y curl wget tar openssl jq
}

# 安装 MTG
install_mtp() {
    echo -e "${YELLOW}正在获取 MTG 最新版本...${PLAIN}"
    local version=$(curl -s https://api.github.com/repos/9seconds/mtg/releases/latest | jq -r .tag_name)
    wget -O mtg.tar.gz "https://github.com/9seconds/mtg/releases/download/${version}/mtg-${version:1}-linux-amd64.tar.gz"
    tar -xvf mtg.tar.gz
    cp mtg-*/mtg ${MTG_BIN}
    chmod +x ${MTG_BIN}
    rm -rf mtg*
}

# 安装 Cloudflared
install_cloudflare() {
    echo -e "${YELLOW}正在安装 Cloudflare Tunnel...${PLAIN}"
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O ${TUNNEL_BIN}
    chmod +x ${TUNNEL_BIN}
}

# 配置服务
setup_service() {
    read -p "请输入 MTProto 监听端口 (默认 443): " MTP_PORT
    MTP_PORT=${MTP_PORT:-443}
    
    read -p "请输入密钥 (留空随机生成): " MTP_SECRET
    if [[ -z "$MTP_SECRET" ]]; then
        MTP_SECRET=$(openssl rand -hex 16)
    fi

    # 写入配置文件
    cat > ${WORK_DIR}/config.env <<EOF
MTP_PORT=${MTP_PORT}
MTP_SECRET=${MTP_SECRET}
EOF

    # 创建 Systemd 服务 (MTG)
    cat > /etc/systemd/system/mtp.service <<EOF
[Unit]
Description=MTProto Proxy Service
After=network.target

[Service]
ExecStart=${MTG_BIN} run -b 0.0.0.0:${MTP_PORT} ${MTP_SECRET}
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable mtp
    systemctl start mtp
    
    echo -e "${GREEN}MTProto 服务已启动！端口: ${MTP_PORT}, 密钥: ${MTP_SECRET}${PLAIN}"
}

# 配置 Cloudflare Tunnel
setup_tunnel() {
    echo -e "${YELLOW}请确保你已经有一个 Cloudflare 账户。${PLAIN}"
    echo -e "1. 执行: cloudflared tunnel login (手动在另一个窗口登录)"
    echo -e "2. 然后在这里输入你的 Tunnel Token 或者按照提示操作。"
    read -p "请输入 Cloudflare Tunnel Token (若不使用隧道请直接回车): " CF_TOKEN
    
    if [[ -n "$CF_TOKEN" ]]; then
        cat > /etc/systemd/system/cf-tunnel.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
ExecStart=${TUNNEL_BIN} tunnel --no-autoupdate run --token ${CF_TOKEN}
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
        systemctl enable cf-tunnel
        systemctl start cf-tunnel
        echo -e "${GREEN}Cloudflare Tunnel 已配置完成并启动。${PLAIN}"
    fi
}

# 管理功能
show_status() {
    echo -e "${YELLOW}--- 服务状态 ---${PLAIN}"
    systemctl status mtp --no-pager | grep Active
    systemctl status cf-tunnel --no-pager | grep Active 2>/dev/null || echo "Cloudflare Tunnel 未配置"
}

view_logs() {
    journalctl -u mtp -n 50 --no-pager
}

# 快捷键设置
setup_shortcut() {
    cat > /usr/local/bin/m <<EOF
#!/bin/bash
bash $(realpath $0)
EOF
    chmod +x /usr/local/bin/m
    echo -e "${GREEN}快捷键 'm' 已设置，之后输入 m 即可进入管理界面。${PLAIN}"
}

# --- 主菜单 ---
main_menu() {
    clear
    echo "========================================"
    echo "    MTProto & Cloudflare 管理脚本"
    echo "========================================"
    echo "1. 安装所有组件 (MTP + Cloudflare)"
    echo "2. 配置/重新配置 MTProto"
    echo "3. 配置 Cloudflare Tunnel"
    echo "4. 启动服务"
    echo "5. 停止服务"
    echo "6. 查看状态"
    echo "7. 查看日志"
    echo "8. 卸载全部"
    echo "0. 退出"
    echo "========================================"
    read -p "请选择功能 (0-8): " num

    case "$num" in
        1)
            install_dependencies
            install_mtp
            install_cloudflare
            setup_service
            setup_shortcut
            ;;
        2)
            setup_service
            ;;
        3)
            setup_tunnel
            ;;
        4)
            systemctl start mtp
            systemctl start cf-tunnel 2>/dev/null
            echo "服务已尝试启动"
            ;;
        5)
            systemctl stop mtp
            systemctl stop cf-tunnel 2>/dev/null
            echo "服务已停止"
            ;;
        6)
            show_status
            ;;
        7)
            view_logs
            ;;
        8)
            systemctl stop mtp cf-tunnel
            systemctl disable mtp cf-tunnel
            rm -rf ${WORK_DIR} ${MTG_BIN} ${TUNNEL_BIN} /etc/systemd/system/mtp.service /etc/systemd/system/cf-tunnel.service /usr/local/bin/m
            echo "已完成卸载"
            ;;
        0)
            exit 0
            ;;
        *)
            echo "无效输入"
            ;;
    esac
    read -p "按回车键返回主菜单..."
    main_menu
}

main_menu
