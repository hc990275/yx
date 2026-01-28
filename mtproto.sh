#!/bin/bash

# =========================================================
#   VPS SOCKS5 代理一键管理脚本 (GOST v2) - 终极管理版
#   架构: 全架构自适应 (x86_64 / ARM64)
#   功能: 端口修改 | 监控与链接合一 | 自动依赖管理
# =========================================================

# --- 基础配置 ---
# 字体颜色配置
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

# 核心路径与服务名
GOST_PATH="/usr/bin/gost"
SERVICE_NAME="gost"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
GOST_VERSION="2.11.5"

# --- 辅助函数 ---

# 检查是否为 Root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：请使用 root 用户运行此脚本！${PLAIN}"
        exit 1
    fi
}

# 获取公网 IP
get_public_ip() {
    PUBLIC_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://icanhazip.com)
    if [[ -z "$PUBLIC_IP" ]]; then
        PUBLIC_IP="127.0.0.1"
    fi
}

# 暂停并返回主菜单
wait_and_return() {
    echo -e ""
    read -n 1 -s -r -p "按任意键回到主菜单..."
    show_menu
}

# 检查依赖
install_dependencies() {
    # 仅在安装时检查，加快其他操作速度
    if [[ "$1" == "check" ]]; then
        echo -e "${YELLOW}>>> 正在检查并更新必要依赖...${PLAIN}"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -y >/dev/null 2>&1
            apt-get install -y wget gzip curl net-tools >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            yum makecache >/dev/null 2>&1
            yum install -y wget gzip curl net-tools >/dev/null 2>&1
        elif command -v dnf >/dev/null 2>&1; then
            dnf makecache >/dev/null 2>&1
            dnf install -y wget gzip curl net-tools >/dev/null 2>&1
        fi
        echo -e "${GREEN}依赖检查完成。${PLAIN}"
    fi
}

# --- 核心功能函数 ---

# 1. 安装代理
install_proxy() {
    echo -e "${SKYBLUE}>>> 开始安装/重装 GOST SOCKS5 代理${PLAIN}"

    install_dependencies "check"
    get_public_ip

    # 架构检测
    echo -e "${YELLOW}正在检测系统架构...${PLAIN}"
    ARCH=$(uname -m)
    GOST_ARCH=""

    case $ARCH in
        x86_64|amd64)
            GOST_ARCH="amd64"
            echo -e "检测结果: ${GREEN}x86_64 (AMD64)${PLAIN}"
            ;;
        aarch64|arm64)
            GOST_ARCH="armv8"
            echo -e "检测结果: ${GREEN}ARM64 (aarch64)${PLAIN}"
            ;;
        *)
            echo -e "${RED}错误: 不支持的系统架构 ($ARCH)${PLAIN}"
            return 1
            ;;
    esac

    # 下载文件
    DOWNLOAD_URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/gost-linux-${GOST_ARCH}-${GOST_VERSION}.gz"
    
    systemctl stop $SERVICE_NAME >/dev/null 2>&1
    rm -f "$GOST_PATH"
    
    echo -e "${GREEN}正在下载 GOST 程序...${PLAIN}"
    wget --no-check-certificate -O gost.gz "$DOWNLOAD_URL"
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}下载失败！请检查网络。${PLAIN}"
        return 1
    fi

    gzip -d gost.gz
    mv gost "$GOST_PATH"
    chmod +x "$GOST_PATH"

    if ! "$GOST_PATH" -V >/dev/null 2>&1; then
        echo -e "${RED}程序无法执行，安装失败。${PLAIN}"
        rm -f "$GOST_PATH"
        return 1
    fi

    # 配置参数
    echo -e ""
    echo -e "${YELLOW}请配置 SOCKS5 代理参数：${PLAIN}"
    read -p "请输入端口 (默认 1080): " PORT
    [[ -z "$PORT" ]] && PORT="1080"

    read -p "请输入用户名 (回车无密码): " USER
    read -p "请输入密码 (回车无密码): " PASS

    if [[ -z "$USER" || -z "$PASS" ]]; then
        EXEC_CMD="$GOST_PATH -L socks5://:$PORT"
    else
        EXEC_CMD="$GOST_PATH -L socks5://${USER}:${PASS}@:$PORT"
    fi

    # 创建服务
    write_service_file "$EXEC_CMD"
    
    # 启动与防火墙
    reload_and_restart
    open_firewall "$PORT"

    # 显示信息
    echo -e ""
    echo -e "${GREEN}安装完成！${PLAIN}"
    view_dashboard "no_wait" # 调用合并后的面板但不暂停
    wait_and_return
}

# 2. 修改端口 (新增功能)
modify_port() {
    if [[ ! -f "$SERVICE_FILE" ]]; then
        echo -e "${RED}服务未安装，无法修改。${PLAIN}"
        wait_and_return
        return
    fi

    echo -e "${SKYBLUE}>>> 修改代理端口${PLAIN}"
    
    # 读取旧配置以保留账号密码
    CMD_LINE=$(grep "ExecStart" "$SERVICE_FILE")
    RAW_CONFIG=$(echo "$CMD_LINE" | sed -n 's/.*socks5:\/\///p')
    
    # 解析旧的认证信息
    if [[ "$RAW_CONFIG" == *"@"* ]]; then
        USER_PASS=$(echo "$RAW_CONFIG" | cut -d'@' -f1)
        OLD_USER=$(echo "$USER_PASS" | cut -d':' -f1)
        OLD_PASS=$(echo "$USER_PASS" | cut -d':' -f2)
        HAS_AUTH=1
    else
        HAS_AUTH=0
    fi

    # 获取新端口
    echo -e "当前配置包含账号密码: $(if [[ $HAS_AUTH -eq 1 ]]; then echo "${GREEN}是${PLAIN}"; else echo "${RED}否${PLAIN}"; fi)"
    read -p "请输入新的端口号: " NEW_PORT
    
    if [[ -z "$NEW_PORT" ]]; then
        echo -e "${RED}端口不能为空！${PLAIN}"
        wait_and_return
        return
    fi

    # 重新构建命令
    if [[ $HAS_AUTH -eq 1 ]]; then
        NEW_EXEC_CMD="$GOST_PATH -L socks5://${OLD_USER}:${OLD_PASS}@:$NEW_PORT"
    else
        NEW_EXEC_CMD="$GOST_PATH -L socks5://:$NEW_PORT"
    fi

    # 写入新配置
    write_service_file "$NEW_EXEC_CMD"
    
    # 重启并应用
    echo -e "${YELLOW}正在应用新端口...${PLAIN}"
    reload_and_restart
    open_firewall "$NEW_PORT"
    
    echo -e "${GREEN}修改成功！${PLAIN}"
    view_dashboard "no_wait"
    wait_and_return
}

# 通用：写入 Service 文件
write_service_file() {
    local CMD=$1
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=GOST SOCKS5 Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=$CMD
Restart=always
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
}

# 通用：重载并重启
reload_and_restart() {
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    systemctl restart "$SERVICE_NAME"
}

# 通用：开放防火墙
open_firewall() {
    local PORT=$1
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$PORT"/tcp >/dev/null 2>&1
        ufw allow "$PORT"/udp >/dev/null 2>&1
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --zone=public --add-port="$PORT"/tcp --permanent >/dev/null 2>&1
        firewall-cmd --zone=public --add-port="$PORT"/udp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    elif command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT >/dev/null 2>&1
        iptables -I INPUT -p udp --dport "$PORT" -j ACCEPT >/dev/null 2>&1
    fi
}

# 3. 卸载代理
uninstall_proxy() {
    echo -e "${YELLOW}正在停止并卸载...${PLAIN}"
    systemctl stop "$SERVICE_NAME"
    systemctl disable "$SERVICE_NAME"
    rm -f "$SERVICE_FILE"
    rm -f "$GOST_PATH"
    systemctl daemon-reload
    echo -e "${GREEN}卸载完成。${PLAIN}"
    wait_and_return
}

# 4/5/7 服务控制
start_proxy() { systemctl start "$SERVICE_NAME"; echo -e "${GREEN}已启动${PLAIN}"; wait_and_return; }
stop_proxy() { systemctl stop "$SERVICE_NAME"; echo -e "${YELLOW}已停止${PLAIN}"; wait_and_return; }
restart_proxy() { systemctl restart "$SERVICE_NAME"; echo -e "${GREEN}已重启${PLAIN}"; wait_and_return; }
check_log() { systemctl status "$SERVICE_NAME" --no-pager; wait_and_return; }

# 6. 综合面板 (监控 + 配置 + TG链接)
view_dashboard() {
    local MODE=$1 # 传入参数控制是否需要 "按任意键返回"
    
    if [[ ! -f "$SERVICE_FILE" ]]; then
        echo -e "${RED}服务未安装。${PLAIN}"
        if [[ "$MODE" != "no_wait" ]]; then wait_and_return; fi
        return
    fi

    # --- 1. 获取配置信息 ---
    get_public_ip
    CMD_LINE=$(grep "ExecStart" "$SERVICE_FILE")
    RAW_CONFIG=$(echo "$CMD_LINE" | sed -n 's/.*socks5:\/\///p')

    if [[ "$RAW_CONFIG" == *"@"* ]]; then
        USER_PASS=$(echo "$RAW_CONFIG" | cut -d'@' -f1)
        CONF_PORT=$(echo "$RAW_CONFIG" | cut -d'@' -f2 | tr -d ':')
        CONF_USER=$(echo "$USER_PASS" | cut -d':' -f1)
        CONF_PASS=$(echo "$USER_PASS" | cut -d':' -f2)
        AUTH_SHOW="${CONF_USER}:${CONF_PASS}"
        TG_LINK="https://t.me/socks?server=${PUBLIC_IP}&port=${CONF_PORT}&user=${CONF_USER}&pass=${CONF_PASS}"
    else
        CONF_PORT=$(echo "$RAW_CONFIG" | tr -d ':')
        AUTH_SHOW="无认证"
        TG_LINK="https://t.me/socks?server=${PUBLIC_IP}&port=${CONF_PORT}"
    fi

    # --- 2. 获取连接数 ---
    if command -v ss >/dev/null 2>&1; then
        CONN_COUNT=$(ss -anp | grep ":${CONF_PORT} " | grep ESTAB | wc -l)
    elif command -v netstat >/dev/null 2>&1; then
        CONN_COUNT=$(netstat -anp | grep ":${CONF_PORT} " | grep ESTABLISHED | wc -l)
    else
        CONN_COUNT="N/A (缺少 net-tools)"
    fi

    # --- 3. 状态检测 ---
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        STATUS_COLOR="${GREEN}运行中 (Active)${PLAIN}"
    else
        STATUS_COLOR="${RED}已停止 (Stopped)${PLAIN}"
    fi

    # --- 4. 统一显示 ---
    echo -e ""
    echo -e "${SKYBLUE}====================================${PLAIN}"
    echo -e "${SKYBLUE}       GOST SOCKS5 状态面板         ${PLAIN}"
    echo -e "${SKYBLUE}====================================${PLAIN}"
    echo -e " 运行状态 : ${STATUS_COLOR}"
    echo -e " 监听端口 : ${SKYBLUE}${CONF_PORT}${PLAIN}"
    echo -e " 实时连接 : ${GREEN}${CONN_COUNT}${PLAIN}"
    echo -e " 公网 IP  : ${SKYBLUE}${PUBLIC_IP}${PLAIN}"
    echo -e " 认证信息 : ${SKYBLUE}${AUTH_SHOW}${PLAIN}"
    echo -e "------------------------------------"
    echo -e "${YELLOW}Telegram 一键连接:${PLAIN}"
    echo -e "${SKYBLUE}${TG_LINK}${PLAIN}"
    echo -e "${SKYBLUE}====================================${PLAIN}"

    if [[ "$MODE" != "no_wait" ]]; then
        wait_and_return
    fi
}

# --- 菜单界面 ---

show_menu() {
    check_root
    clear
    echo -e "${SKYBLUE}====================================${PLAIN}"
    echo -e "${SKYBLUE}   VPS SOCKS5 代理管理脚本 (GOST)   ${PLAIN}"
    echo -e "${SKYBLUE}   架构: 自适应 | 模式: SOCKS5 Only ${PLAIN}"
    echo -e "${SKYBLUE}====================================${PLAIN}"
    echo -e "${GREEN}1.${PLAIN} 安装/重装代理"
    echo -e "${GREEN}2.${PLAIN} 修改代理端口 ${YELLOW}(NEW)${PLAIN}"
    echo -e "${GREEN}3.${PLAIN} 卸载代理"
    echo -e "------------------------------------"
    echo -e "${GREEN}4.${PLAIN} 启动服务"
    echo -e "${GREEN}5.${PLAIN} 停止服务"
    echo -e "${GREEN}6.${PLAIN} 面板: 状态 / 配置 / TG链接"
    echo -e "${GREEN}7.${PLAIN} 重启服务"
    echo -e "${GREEN}8.${PLAIN} 查看系统日志 (Debug)"
    echo -e "------------------------------------"
    echo -e "${GREEN}0.${PLAIN} 退出脚本"
    echo -e ""
    
    read -p "请输入数字 [0-8]: " choice
    case $choice in
        1) install_proxy ;;
        2) modify_port ;;
        3) uninstall_proxy ;;
        4) start_proxy ;;
        5) stop_proxy ;;
        6) view_dashboard ;;
        7) restart_proxy ;;
        8) check_log ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入无效！${PLAIN}"; sleep 1; show_menu ;;
    esac
}

# 脚本入口
show_menu
