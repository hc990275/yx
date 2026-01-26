#!/bin/bash

# ==================================================
# 脚本名称: MTProto 融合版 (eooce风格 + Python核心)
# 解决痛点: 解决原版在部分 VPS 上二进制不兼容无法启动的问题
# ==================================================

# 颜色定义 (保持原版)
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }

# 基础变量
WORKDIR="$HOME/mtp"
mkdir -p "$WORKDIR"

# 清理旧进程 (同时查杀 go版和python版)
pkill -x mtg >/dev/null 2>&1
pkill -f "mtprotoproxy.py" >/dev/null 2>&1

# 1. 环境检查与安装 (Python环境)
check_env() {
    # 检查是否安装了 net-tools 和 python
    if ! command -v netstat >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
        yellow "正在安装环境依赖..."
        if [ -f /etc/debian_version ]; then
            apt-get update -y
            apt-get install -y net-tools git python3 python3-pip curl || true
            apt-get install -y python3-cryptography python3-uvloop || true
        elif [ -f /etc/redhat-release ]; then
            yum install -y net-tools git python3 python3-pip curl || true
        fi
    fi
}

# 2. 端口检查 (保持 eooce 逻辑)
check_port() {
    read -p "请输入MTProto代理端口(直接回车则使用随机端口): " port
    
    while true; do
        if [[ -z $port ]]; then
            port=$(shuf -i 20000-60000 -n 1)
            yellow "使用随机端口: $port"
        fi
        
        # 检查占用
        if netstat -tlunp | grep -q ":$port "; then
            red "端口 ${port} 已被占用，尝试其他端口..."
            port=""
            continue
        else
            green "使用 $port 作为TG代理端口"
            MTP_PORT=$port
            export MTP_PORT
            break
        fi
    done
}

# 3. 获取IP
get_ip() {
    IP1=$(curl -s 4.ipw.cn)
    if [[ -z "$IP1" ]]; then
        IP1=$(curl -s ifconfig.me)
    fi
    if [[ -z "$IP1" ]]; then
        red "无法获取公网IP，请检查网络"
        exit 1
    fi
    green "获取到IP: $IP1"
}

# 4. 下载并运行 (核心替换为 Python)
download_run(){
    cd ${WORKDIR}
    
    # 替换为 Python 源码下载
    if [ ! -d "mtprotoproxy" ]; then
        yellow "正在拉取 Python 核心源码..."
        git clone https://github.com/alexbers/mtprotoproxy.git .
    fi

    # 生成密钥
    if [[ -z "$SECRET" ]]; then
        SECRET=$(head -c 16 /dev/urandom | xxd -ps)
    fi

    # 生成配置文件 (解决启动报错的关键)
    cat <<EOF > config.py
PORT = ${MTP_PORT}
USERS = {
    "default": "${SECRET}"
}
import multiprocessing
ADVERTISED_TAG = "00000000000000000000000000000000"
EOF

    # 运行 (使用 nohup 后台运行 Python)
    nohup python3 mtprotoproxy.py > mtg.log 2>&1 &
    
    sleep 3
    if pgrep -f "mtprotoproxy.py" > /dev/null; then
        green "MTProto 代理已启动 (Python版)"
    else
        red "启动失败，请查看日志: cat $WORKDIR/mtg.log"
        cat mtg.log
        exit 1
    fi
}

# 5. 生成信息 (保持原版风格)
generate_info() {
    purple "\n分享链接:\n"
    LINKS="tg://proxy?server=$IP1&port=$MTP_PORT&secret=$SECRET"
    green "$LINKS\n"
    echo -e "$LINKS" > link.txt

    # 生成 restart.sh (适配 Python)
    cat > ${WORKDIR}/restart.sh <<EOF
#!/bin/bash
pkill -f "mtprotoproxy.py"
cd ${WORKDIR}
nohup python3 mtprotoproxy.py > mtg.log 2>&1 &
echo "已重启服务"
EOF
    chmod +x ${WORKDIR}/restart.sh
    purple "提示: 已生成 restart.sh，如果进程停止可运行 ./restart.sh 重启"
    purple "提示: 链接已保存到 link.txt"
}

# 主流程
main() {
    check_env
    check_port
    get_ip
    download_run
    generate_info
}

# 执行
main