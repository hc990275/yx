#!/bin/bash

# ==================================================
# 脚本修改自: eooce (适配 Linux VPS 通用版)
# 功能: 自动获取IP、自定义端口、后台运行、生成链接
# ==================================================

# 1. 定义颜色函数 (保留原风格)
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }

# 2. 初始化变量
WORKDIR="$HOME/mtp"
mkdir -p "$WORKDIR"

# 3. 检查并清理旧进程
check_and_kill() {
    if pgrep -x "mtg" > /dev/null; then
        yellow "检测到旧的 mtg 进程，正在停止..."
        pkill -x mtg
    fi
}

# 4. 获取本机公网 IP (修改为通用方式)
get_ip() {
    # 尝试多个源获取 IP
    IP=$(curl -s 4.ipw.cn)
    if [[ -z "$IP" ]]; then
        IP=$(curl -s ifconfig.me)
    fi
    
    if [[ -z "$IP" ]]; then
        red "无法获取公网 IP，请检查网络！"
        exit 1
    fi
    green "获取到本机 IP: $IP"
}

# 5. 设置端口 (去除 devil 命令，改为手动输入或随机)
check_port() {
    read -p "请输入 MTProto 端口 (回车随机 20000-60000): " input_port
    if [[ -z "$input_port" ]]; then
        MTP_PORT=$((RANDOM % 40000 + 20000))
    else
        MTP_PORT=$input_port
    fi
    
    # 简单检查端口占用
    if netstat -tlunp 2>/dev/null | grep -q ":$MTP_PORT "; then
        red "端口 $MTP_PORT 已被占用，请重新运行脚本更换端口！"
        exit 1
    fi
    
    green "使用端口: $MTP_PORT"
}

# 6. 生成密钥
get_secret() {
    # 使用 openssl 生成标准的 hex 密钥
    if command -v openssl >/dev/null; then
        SECRET=$(openssl rand -hex 16)
    else
        # 如果没有 openssl，用备用方法
        SECRET=$(head -c 16 /dev/urandom | xxd -ps)
    fi
    # echo "密钥: $SECRET"
}

# 7. 下载并运行 (核心修改：改为下载 Linux 版本)
download_run() {
    cd "$WORKDIR"
    
    yellow "正在下载主程序..."
    
    # 判断架构
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        # 下载 Linux amd64 版本 (使用官方稳定源)
        wget -q -O mtg "https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-amd64"
    elif [[ "$ARCH" == "aarch64" ]]; then
        # 下载 Linux arm64 版本
        wget -q -O mtg "https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-arm64"
    else
        red "不支持的架构: $ARCH"
        exit 1
    fi

    if [ ! -f "mtg" ]; then
        # 如果上面下载失败，尝试下载 tar 包解压 (备用方案)
        wget -q -O mtg.tar.gz "https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-amd64.tar.gz"
        tar -xzf mtg.tar.gz
        mv mtg-*-linux-*/mtg .
        rm -rf mtg-*-linux-* mtg.tar.gz
    fi

    if [ ! -f "mtg" ]; then
        red "下载失败，请检查网络。"
        exit 1
    fi

    chmod +x mtg
    
    yellow "正在启动..."
    # 使用 nohup 后台运行 (原作者的逻辑，不依赖 systemd)
    nohup ./mtg simple-run -n 0.0.0.0:$MTP_PORT $SECRET > mtg.log 2>&1 &
    
    sleep 2
    
    if pgrep -x "mtg" > /dev/null; then
        green "启动成功！"
    else
        red "启动失败！可能是二进制文件不兼容。"
        red "查看日志: cat $WORKDIR/mtg.log"
        exit 1
    fi
}

# 8. 显示连接信息
show_info() {
    purple "\n========================================"
    purple "       MTProto 代理连接信息"
    purple "========================================"
    echo -e "IP: \t\e[1;33m$IP\033[0m"
    echo -e "端口: \t\e[1;33m$MTP_PORT\033[0m"
    echo -e "密钥: \t\e[1;33m$SECRET\033[0m"
    purple "----------------------------------------"
    
    LINK="tg://proxy?server=$IP&port=$MTP_PORT&secret=$SECRET"
    green "TG 一键链接:"
    echo -e "\e[4;34m$LINK\033[0m"
    
    # 保存链接到文件
    echo "$LINK" > "$WORKDIR/link.txt"
    purple "========================================"
    yellow "提示: 进程已在后台运行。如需停止，请运行: pkill -x mtg"
}

# === 主逻辑 ===
main() {
    # 检查基础依赖
    if [ -f /etc/debian_version ]; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y wget curl net-tools openssl >/dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        yum install -y wget curl net-tools openssl >/dev/null 2>&1
    fi

    check_and_kill
    get_ip
    check_port
    get_secret
    download_run
    show_info
}

main