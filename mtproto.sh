#!/bin/bash

# =========================================================
# 脚本名称: MTProto + Cloudflare Tunnel 旗舰版
# 脚本版本: v1.0.4 (2025-12-30)
# 修复内容: 修正 v2.1.7 官方下载链接 404 问题，增加文件校验
# =========================================================

# --- 变量定义 ---
MTG_BIN="/usr/local/bin/mtg"
MTG_SERVICE="/etc/systemd/system/mtg.service"
MTG_CONF="/etc/mtg_info"
SHORTCUT_BIN="/usr/local/bin/m"
VERSION="v1.0.4"

# 颜色
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[36m'
PLAIN='\033[0m'

# --- 基础检查 ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 请使用 root 用户运行此脚本！${PLAIN}"
        exit 1
    fi
}

# --- 核心安装逻辑 ---
install_services() {
    echo -e "${BLUE}=== 开始安装 (版本: $VERSION) ===${PLAIN}"
    
    # 1. 安装依赖
    if [ -f /etc/debian_version ]; then
        apt-get update -y
        apt-get install -y wget curl tar jq lsof
    elif [ -f /etc/redhat-release ]; then
        yum install -y wget curl tar jq lsof
    fi

    # 2. 收集用户配置
    echo -e "\n${YELLOW}--- 配置参数 ---${PLAIN}"
    read -p "1. 请输入 MTProto 监听端口 (建议 18443): " MY_PORT
    read -p "2. 请输入伪装域名 (默认 google.com): " MY_DOMAIN
    [[ -z "$MY_DOMAIN" ]] && MY_DOMAIN="google.com"
    read -p "3. 请输入 Cloudflare Tunnel Token: " CF_TOKEN
    
    # 3. 下载 MTG (关键修复点)
    echo -e "\n${BLUE}正在下载 MTG v2.1.7...${PLAIN}"
    
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        # 修正后的正确文件名
        FILE_NAME="mtg-2.1.7-linux-amd64.tar.gz"
        DOWNLOAD_URL="https://github.com/9seconds/mtg/releases/download/v2.1.7/${FILE_NAME}"
    elif [[ "$ARCH" == "aarch64" ]]; then
        FILE_NAME="mtg-2.1.7-linux-arm64.tar.gz"
        DOWNLOAD_URL="https://github.com/9seconds/mtg/releases/download/v2.1.7/${FILE_NAME}"
    else
        echo -e "${RED}不支持的架构: $ARCH${PLAIN}"
        exit 1
    fi

    wget -O mtg.tar.gz "$DOWNLOAD_URL"
    
    # 强制校验：如果文件太小或下载失败，直接退出
    if [[ ! -s mtg.tar.gz ]]; then
        echo -e "${RED}错误：MTG 下载失败 (404 或网络问题)。请检查 GitHub 连接。${PLAIN}"
        rm -f mtg.tar.gz
        exit 1
    fi

    # 解压并安装
    rm -rf mtg_temp
    mkdir -p mtg_temp
    tar -xzf mtg.tar.gz -C mtg_temp --strip-components=1
    
    # 移动二进制文件
    if [[ -f "mtg_temp/mtg" ]]; then
        mv mtg_temp/mtg "$MTG_BIN"
    else
        # 尝试查找解压目录下的文件
        find mtg_temp -name "mtg" -exec mv {} "$MTG_BIN" \;
    fi
    
    chmod +x "$MTG_BIN"
    rm -rf mtg.tar.gz mtg_temp

    # 二次校验二进制文件
    if [[ ! -f "$MTG_BIN" ]]; then
        echo -e "${RED}严重错误：解压后未找到 mtg 文件，安装终止。${PLAIN}"
        exit 1
    fi

    # 4. 生成密钥 (Secret)
    echo -e "${YELLOW}正在生成密钥...${PLAIN}"
    MY_SECRET=$($MTG_BIN generate-secret --hex "$MY_DOMAIN")
    
    if [[ -z "$MY_SECRET" ]]; then
        echo -e "${RED}错误：密钥生成失败。${PLAIN}"
        exit 1
    fi

    # 5. 保存配置 (持久化)
    cat > "$MTG_CONF" <<EOF
PORT=$MY_PORT
DOMAIN=$MY_DOMAIN
SECRET=$MY_SECRET
VERSION=$VERSION
EOF

    # 6. 配置 Systemd 服务
    cat > "$MTG_SERVICE" <<EOF
[Unit]
Description=MTG Proxy
After=network.target

[Service]
Type=simple
ExecStart=$MTG_BIN simple-run -b 0.0.0.0:$MY_PORT $MY_SECRET
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    # 7. 安装 Cloudflare Tunnel
    echo -e "\n${BLUE}配置 Cloudflare Tunnel...${PLAIN}"
    if [[ "$ARCH" == "x86_64" ]]; then
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    else
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
    fi
    dpkg -i cloudflared.deb && rm cloudflared.deb
    
    cloudflared service uninstall 2>/dev/null
    cloudflared service install "$CF_TOKEN"

    # 8. 启动所有服务
    systemctl daemon-reload
    systemctl enable mtg
    systemctl restart mtg
    systemctl restart cloudflared

    # 9. 创建快捷键
    cp "$0" "$SHORTCUT_BIN" && chmod +x "$SHORTCUT_BIN"
    
    echo -e "${GREEN}安装完成！${PLAIN}"
    show_tg_link
}

# --- 查看连接信息 ---
show_tg_link() {
    # 尝试读取配置文件
    if [ -f "$MTG_CONF" ]; then
        source "$MTG_CONF"
    fi
    
    # 兜底：如果配置文件里没有 Secret，尝试从进程或服务文件里抓
    if [[ -z "$SECRET" ]]; then
        SECRET=$(grep -oP 'simple-run -b 0.0.0.0:\d+ \K\S+' "$MTG_SERVICE" 2>/dev/null)
    fi

    echo -e "\n${BLUE}========== Telegram 连接信息 ==========${PLAIN}"
    if [[ -z "$SECRET" ]]; then
        echo -e "${RED}无法获取密钥，请检查 MTG 服务是否正常安装。${PLAIN}"
    else
        echo -e "注意：端口固定为 ${YELLOW}443${PLAIN} (走 CF 隧道)"
        read -p "请输入你在 CF 后台绑定的域名 (如 aaa.abcai.online): " USER_DOMAIN
        
        if [[ -n "$USER_DOMAIN" ]]; then
            LINK="https://t.me/proxy?server=${USER_DOMAIN}&port=443&secret=${SECRET}"
            echo -e "\n${GREEN}直连链接 (点击即可):${PLAIN}"
            echo -e "${YELLOW}${LINK}${PLAIN}"
            echo -e "\n参数详情: Server=${USER_DOMAIN}, Port=443, Secret=${SECRET}"
        fi
    fi
    echo -e "=======================================\n"
    read -p "按回车返回..."
}

# --- 卸载 ---
uninstall_all() {
    read -p "确定卸载所有服务吗？(y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        systemctl stop mtg cloudflared
        systemctl disable mtg cloudflared
        rm -f "$MTG_BIN" "$MTG_SERVICE" "$MTG_CONF" "$SHORTCUT_BIN"
        cloudflared service uninstall 2>/dev/null
        apt-get remove -y cloudflared 2>/dev/null
        echo -e "${GREEN}卸载完毕。${PLAIN}"
    fi
}

# --- 菜单 ---
main_menu() {
    clear
    echo -e "${BLUE}=========================================${PLAIN}"
    echo -e "    MTProto + CF 管理脚本 [${YELLOW}$VERSION${BLUE}]    "
    echo -e "=========================================${PLAIN}"
    echo -e "1. ${GREEN}安装/重装${PLAIN} (修复下载 404)"
    echo -e "2. 查看 Telegram 连接"
    echo -e "3. 查看状态"
    echo -e "4. 查看日志"
    echo -e "5. 卸载服务"
    echo -e "0. 退出"
    echo -e "${BLUE}=========================================${PLAIN}"
    read -p "请输入数字 [0-5]: " num

    case "$num" in
        1) install_services ;;
        2) show_tg_link ;;
        3) 
            echo -e "--- MTG 状态 ---"
            systemctl status mtg --no-pager
            echo -e "\n--- Cloudflare 状态 ---"
            systemctl status cloudflared --no-pager
            read -p "按回车继续..." ;;
        4) journalctl -u mtg -f ;;
        5) uninstall_all ;;
        0) exit 0 ;;
        *) main_menu ;;
    esac
}

check_root
main_menu
