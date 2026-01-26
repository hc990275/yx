#!/bin/bash

# =========================================================
# 脚本名称: MTProto Proxy (最终完美版 V4)
# 修正内容: 修复 config.py 格式颠倒问题，彻底消除 Bad Secret 报错
# =========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'
WORKDIR="/opt/mtproto_proxy"

# 检查 Root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 请使用 root 用户运行此脚本。${PLAIN}"
    exit 1
fi

# =========================================================
# 1. 环境安装
# =========================================================
install_env() {
    echo -e "${YELLOW}>>> [1/4] 检查 Python 环境...${PLAIN}"
    if [ -f /etc/debian_version ]; then
        apt-get update -y
        apt-get install -y git python3 python3-pip curl grep || true
        apt-get install -y python3-cryptography python3-uvloop || true
    elif [ -f /etc/redhat-release ]; then
        yum update -y
        yum install -y git python3 python3-pip curl grep || true
    fi
}

# =========================================================
# 2. 安装并启动
# =========================================================
install_and_run() {
    install_env

    # 1. 停止旧进程
    pkill -f "mtprotoproxy.py"
    
    # 2. 准备目录
    if [ ! -d "$WORKDIR" ]; then
        echo -e "${YELLOW}>>> [2/4] 拉取源码...${PLAIN}"
        git clone https://github.com/alexbers/mtprotoproxy.git "$WORKDIR"
    fi
    
    cd "$WORKDIR"

    # 3. 设置端口
    DEFAULT_PORT=$((RANDOM % 10000 + 20000))
    read -p "请输入端口 (默认 $DEFAULT_PORT): " INPUT_PORT
    PROXY_PORT=${INPUT_PORT:-$DEFAULT_PORT}
    
    # 生成 32 字符 Hex 密钥
    PROXY_SECRET=$(head -c 16 /dev/urandom | xxd -ps)

    # 4. 生成 config.py (关键修正：USERS 格式修正为 "用户名": "密钥")
    echo -e "${YELLOW}>>> [3/4] 生成配置文件...${PLAIN}"
    
    cat <<EOF > config.py
PORT = ${PROXY_PORT}

# 格式必须是: "用户名": "32位Hex密钥"
USERS = {
    "my_user": "${PROXY_SECRET}"
}

import multiprocessing
ADVERTISED_TAG = "00000000000000000000000000000000"
EOF

    # 5. 启动服务
    echo -e "${YELLOW}>>> [4/4] 正在启动服务...${PLAIN}"
    
    rm -f log.txt
    # 后台静默启动
    nohup python3 mtprotoproxy.py > log.txt 2>&1 &
    
    sleep 3
    
    # 6. 检查状态
    if pgrep -f "mtprotoproxy.py" > /dev/null; then
        show_info_direct $PROXY_PORT $PROXY_SECRET
    else
        echo -e "${RED}启动失败！请查看日志:${PLAIN}"
        cat log.txt
    fi
}

# =========================================================
# 3. 显示信息
# =========================================================
show_info_direct() {
    local port=$1
    local secret=$2
    local ip=$(curl -s 4.ipw.cn || curl -s ifconfig.me)

    echo "========================================================"
    echo -e "   ${GREEN}MTProto 代理 (运行正常)${PLAIN}"
    echo "========================================================"
    echo -e "IP 地址: ${YELLOW}$ip${PLAIN}"
    echo -e "端口   : ${YELLOW}$port${PLAIN}"
    echo -e "密钥   : ${YELLOW}$secret${PLAIN}"
    echo "--------------------------------------------------------"
    echo -e "TG 链接: ${GREEN}tg://proxy?server=${ip}&port=${port}&secret=${secret}${PLAIN}"
    echo "========================================================"
}

# 从 config.py 读取信息
read_config_info() {
    if [ ! -f "$WORKDIR/config.py" ]; then
        echo "未找到配置文件。"
        return
    fi
    local port=$(grep "^PORT =" "$WORKDIR/config.py" | awk -F'= ' '{print $2}')
    # 修正读取正则
    local secret=$(grep -oP '"[0-9a-f]{32}"' "$WORKDIR/config.py" | head -1 | tr -d '"')
    local ip=$(curl -s 4.ipw.cn)
    
    echo -e "端口: $port"
    echo -e "密钥: $secret"
    echo -e "链接: ${GREEN}tg://proxy?server=${ip}&port=${port}&secret=${secret}${PLAIN}"
}

stop_proxy() {
    pkill -f "mtprotoproxy.py"
    echo -e "${GREEN}服务已停止。${PLAIN}"
}

view_log() {
    [ -f "$WORKDIR/log.txt" ] && tail -n 20 "$WORKDIR/log.txt" || echo "无日志"
}

# =========================================================
# 菜单
# =========================================================
show_menu() {
    clear
    echo "========================================================"
    echo -e "${GREEN}MTProto 最终完美版 V4${PLAIN}"
    echo "========================================================"
    echo "1. 安装并启动 (Install & Start)"
    echo "2. 查看连接信息 (Show Info)"
    echo "3. 停止服务 (Stop)"
    echo "4. 查看日志 (Log)"
    echo "0. 退出"
    echo "========================================================"
    read -p "选项: " num
    case "$num" in
        1) install_and_run ;;
        2) read_config_info ;;
        3) stop_proxy ;;
        4) view_log ;;
        0) exit 0 ;;
        *) echo "无效输入" ;;
    esac
}

show_menu