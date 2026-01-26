#!/bin/bash

# =========================================================
# 脚本名称: MTProto Proxy (配置文件版 - 修复启动报错)
# 核心原理: 生成 config.py 配置文件，避免命令行参数解析错误
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
        # 强制安装，忽略错误
        apt-get install -y git python3 python3-pip curl grep || true
        apt-get install -y python3-cryptography python3-uvloop || true
    elif [ -f /etc/redhat-release ]; then
        yum update -y
        yum install -y git python3 python3-pip curl grep || true
    fi

    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}Python3 安装失败，请尝试手动安装。${PLAIN}"
        exit 1
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
    else
        echo -e "${YELLOW}>>> 源码目录已存在，跳过下载。${PLAIN}"
    fi
    
    if [ ! -f "$WORKDIR/mtprotoproxy.py" ]; then
        echo -e "${RED}源码文件缺失，请删除 $WORKDIR 目录后重试。${PLAIN}"
        return
    fi

    cd "$WORKDIR"

    # 3. 设置端口和密钥
    DEFAULT_PORT=$((RANDOM % 10000 + 20000))
    read -p "请输入端口 (默认 $DEFAULT_PORT): " INPUT_PORT
    PROXY_PORT=${INPUT_PORT:-$DEFAULT_PORT}
    
    # 生成 32 字符 Hex 密钥
    PROXY_SECRET=$(head -c 16 /dev/urandom | xxd -ps)

    # 4. 生成 config.py (关键修复步骤)
    echo -e "${YELLOW}>>> [3/4] 生成配置文件 (config.py)...${PLAIN}"
    
    cat <<EOF > config.py
PORT = ${PROXY_PORT}

# 用户列表: { "密钥": "用户名" }
USERS = {
    "${PROXY_SECRET}": "default_user"
}

# 开启多线程模式 (根据 CPU 核心数)
import multiprocessing
ADVERTISED_TAG = "00000000000000000000000000000000"
EOF

    # 5. 启动服务 (不带参数启动，让它读取 config.py)
    echo -e "${YELLOW}>>> [4/4] 正在启动服务...${PLAIN}"
    
    # 清理旧日志
    rm -f log.txt
    
    # nohup 后台启动，不传任何参数！
    nohup python3 mtprotoproxy.py > log.txt 2>&1 &
    
    sleep 3
    
    # 6. 检查状态
    if pgrep -f "mtprotoproxy.py" > /dev/null; then
        show_info_direct $PROXY_PORT $PROXY_SECRET
    else
        echo -e "${RED}启动失败！这是最新的报错日志:${PLAIN}"
        echo "----------------------------------------"
        cat log.txt
        echo "----------------------------------------"
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
    echo -e "   ${GREEN}MTProto 代理 (Config模式) 运行中${PLAIN}"
    echo "========================================================"
    echo -e "IP 地址: ${YELLOW}$ip${PLAIN}"
    echo -e "端口   : ${YELLOW}$port${PLAIN}"
    echo -e "密钥   : ${YELLOW}$secret${PLAIN}"
    echo "--------------------------------------------------------"
    echo -e "TG 链接: ${GREEN}tg://proxy?server=${ip}&port=${port}&secret=${secret}${PLAIN}"
    echo "========================================================"
    echo -e "${YELLOW}提示: 如果需要修改端口/密钥，直接编辑 $WORKDIR/config.py 然后重启脚本即可。${PLAIN}"
}

# 读取 config.py 显示信息
read_config_info() {
    if [ ! -f "$WORKDIR/config.py" ]; then
        echo "未找到配置文件。"
        return
    fi
    
    cd "$WORKDIR"
    # 简单的 grep 提取，并不完美但够用
    local port=$(grep "^PORT =" config.py | awk -F'= ' '{print $2}')
    local secret=$(grep -oP '"[0-9a-f]{32}"' config.py | head -1 | tr -d '"')
    local ip=$(curl -s 4.ipw.cn)
    
    echo "当前配置 (从文件读取):"
    echo "端口: $port"
    echo "密钥: $secret"
    echo -e "链接: ${GREEN}tg://proxy?server=${ip}&port=${port}&secret=${secret}${PLAIN}"
}

# =========================================================
# 4. 辅助功能
# =========================================================
stop_proxy() {
    pkill -f "mtprotoproxy.py"
    echo -e "${GREEN}服务已停止。${PLAIN}"
}

view_log() {
    if [ -f "$WORKDIR/log.txt" ]; then
        tail -n 20 "$WORKDIR/log.txt"
    else
        echo "暂无日志文件。"
    fi
}

# =========================================================
# 菜单
# =========================================================
show_menu() {
    clear
    echo "========================================================"
    echo -e "${GREEN}MTProto 修复版 (Config Mode)${PLAIN}"
    echo "========================================================"
    echo "1. 安装并启动 (Install & Start)"
    echo "2. 查看连接信息 (Read Config)"
    echo "3. 停止服务 (Stop)"
    echo "4. 查看运行日志 (View Log)"
    echo "0. 退出"
    echo "========================================================"
    read -p "请输入选项: " num

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