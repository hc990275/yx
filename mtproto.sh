#!/bin/bash

# ==================================================
# 脚本修改自: eooce (Linux 移植修复版)
# 核心修改: 
# 1. 移除 devil (Serv00专用) 命令，改为 Linux 通用命令
# 2. 替换 FreeBSD 二进制文件为 Linux 版
# 3. 修复原代码中的语法错误
# ==================================================

# 颜色函数 (保留原版)
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }

# 基础变量
HOSTNAME=$(hostname)
USERNAME=$(whoami)
# 生成密钥: 如果没设置就根据用户名生成，或者随机生成
export SECRET=${SECRET:-$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | xxd -ps)}
WORKDIR="$HOME/mtp"
mkdir -p "$WORKDIR"

# 清理旧进程
pgrep -x mtg > /dev/null && pkill -9 mtg >/dev/null 2>&1

# 1. 端口检查函数 (修改为 Linux 版)
check_port() {
    # 安装必要工具
    if ! command -v netstat >/dev/null; then
        if [ -f /etc/debian_version ]; then
            apt-get update -y && apt-get install -y net-tools
        elif [ -f /etc/redhat-release ]; then
            yum install -y net-tools
        fi
    fi

    echo -e "\033[1;35m请输入MTProto代理端口(直接回车则使用随机端口): \033[0m"
    read -p "" port
    
    while true; do
        if [[ -z $port ]]; then
            port=$(shuf -i 20000-60000 -n 1)
            yellow "使用随机端口: $port"
        fi
        
        # 检查端口占用 (使用 netstat 替代 devil)
        if netstat -tlunp | grep -q ":$port "; then
            red "端口 ${port} 已经被占用，正在重新生成..."
            port=""
            continue
        else
            green "端口 $port 可用"
            MTP_PORT=$port
            break
        fi
    done
}

# 2. 获取 IP 函数 (修改为 Linux 版)
get_ip() {
    # 移除 devil vhost 逻辑，改为 curl 获取
    IP1=$(curl -s 4.ipw.cn)
    if [[ -z "$IP1" ]]; then
        IP1=$(curl -s ifconfig.me)
    fi
    
    if [[ -z "$IP1" ]]; then
        red "无法获取公网 IP，请检查网络"
        exit 1
    fi
    green "获取到公网 IP: $IP1"
}

# 3. 下载并运行函数 (修改为 Linux 版下载源)
download_run(){
    cd ${WORKDIR}
    
    # 检测架构
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        # 9seconds/mtg 官方 Linux amd64
        DL_URL="https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-amd64.tar.gz"
    elif [[ "$ARCH" == "aarch64" ]]; then
        # 9seconds/mtg 官方 Linux arm64
        DL_URL="https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-arm64.tar.gz"
    else
        red "不支持的架构: $ARCH"
        exit 1
    fi

    # 下载或检查是否存在
    if [ ! -f "mtg" ]; then
        yellow "正在下载主程序..."
        wget -q -O mtg.tar.gz "$DL_URL"
        if [ $? -ne 0 ]; then
            red "下载失败！"
            exit 1
        fi
        tar -xzf mtg.tar.gz
        mv mtg-*-linux-*/mtg .
        rm -rf mtg-*-linux-* mtg.tar.gz
        chmod +x mtg
    fi

    # 运行 (使用 nohup 后台运行)
    # 注意: 新版 mtg 使用 simple-run 命令
    nohup ./mtg simple-run -n 0.0.0.0:$MTP_PORT $SECRET > mtg.log 2>&1 &
    
    sleep 2
    if pgrep -x "mtg" > /dev/null; then
        green "MTProto 代理启动成功！"
    else
        red "启动失败，请查看目录下的 mtg.log"
        cat mtg.log
        exit 1
    fi
}

# 4. 生成信息和重启脚本 (保留原版逻辑)
generate_info() {
    purple "\n====================================="
    purple "          分享链接 (已保存到 link.txt)"
    purple "====================================="
    
    LINK="tg://proxy?server=$IP1&port=$MTP_PORT&secret=$SECRET"
    echo -e "$LINK"
    echo -e "$LINK" > link.txt

    # 生成重启脚本 restart.sh
    cat > restart.sh <<EOF
#!/bin/bash
pkill -x mtg
cd $WORKDIR
nohup ./mtg simple-run -n 0.0.0.0:$MTP_PORT $SECRET > mtg.log 2>&1 &
echo "已重启 mtg"
EOF
    chmod +x restart.sh
    
    purple "\n提示: 目录下已生成 restart.sh，进程挂掉可直接运行 ./restart.sh 重启"
}

# === 主流程 ===
main() {
    check_port
    get_ip
    download_run
    generate_info
}

main