#!/bin/bash

# ==================================================
# 修复说明：
# 1. 删除了你粘贴时头部多余的乱码 (break_end ;;)
# 2. 修复了 wget 可能未安装的问题
# 3. 修正了下载链接，确保 Linux 系统能正常下载
# ==================================================

red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }

HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')
export SECRET=${SECRET:-$(echo -n "$USERNAME+$HOSTNAME" | md5sum | head -c 32)}
WORKDIR="$HOME/mtp" && mkdir -p "$WORKDIR"
pgrep -x mtg > /dev/null && pkill -9 mtg >/dev/null 2>&1

# 自动安装 wget (防止报错)
if ! command -v wget >/dev/null 2>&1; then
    if [ -f /etc/debian_version ]; then
        apt-get update && apt-get install -y wget
    elif [ -f /etc/redhat-release ]; then
        yum install -y wget
    fi
fi

# 原脚本的 check_port 逻辑 (保留 Serv00 逻辑，但在普通 VPS 不会触发)
check_port () {
  port_list=$(devil port list)
  tcp_ports=$(echo "$port_list" | grep -c "tcp")
  udp_ports=$(echo "$port_list" | grep -c "udp")

  if [[ $tcp_ports -lt 1 ]]; then
      red "没有可用的TCP端口,正在调整..."
      if [[ $udp_ports -ge 3 ]]; then
          udp_port_to_delete=$(echo "$port_list" | awk '/udp/ {print $1}' | head -n 1)
          devil port del udp $udp_port_to_delete
          green "已删除udp端口: $udp_port_to_delete"
      fi
      while true; do
          tcp_port=$(shuf -i 10000-65535 -n 1)
          result=$(devil port add tcp $tcp_port 2>&1)
          if [[ $result == *"Ok"* ]]; then
              green "已添加TCP端口: $tcp_port"
              tcp_port1=$tcp_port
              break
          else
              yellow "端口 $tcp_port 不可用，尝试其他端口..."
          fi
      done
  else
      tcp_ports=$(echo "$port_list" | awk '/tcp/ {print $1}')
      tcp_port1=$(echo "$tcp_ports" | sed -n '1p')
  fi
  devil binexec on >/dev/null 2>&1
  MTP_PORT=$tcp_port1
  green "使用 $MTP_PORT 作为TG代理端口"
}

get_ip() {
    IP_LIST=($(devil vhost list | awk '/^[0-9]+/ {print $1}'))
    API_URL="https://status.eooce.com/api"
    IP1=""; IP2=""; IP3=""
    AVAILABLE_IPS=()

    for ip in "${IP_LIST[@]}"; do
        RESPONSE=$(curl -s --max-time 2 "${API_URL}/${ip}")
        if [[ -n "$RESPONSE" ]] && [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
            AVAILABLE_IPS+=("$ip")
        fi
    done

    [[ ${#AVAILABLE_IPS[@]} -ge 1 ]] && IP1=${AVAILABLE_IPS[0]}
    [[ ${#AVAILABLE_IPS[@]} -ge 2 ]] && IP2=${AVAILABLE_IPS[1]}
    [[ ${#AVAILABLE_IPS[@]} -ge 3 ]] && IP3=${AVAILABLE_IPS[2]}

    if [[ -z "$IP1" ]]; then
        red "所有IP都被墙, 请更换服务器安装"
        exit 1
    fi
}

download_run(){
    if [ -e "${WORKDIR}/mtg" ]; then
        cd ${WORKDIR} && chmod +x mtg
        nohup ./mtg run -b 0.0.0.0:$MTP_PORT $SECRET --stats-bind=127.0.0.1:$MTP_PORT >/dev/null 2>&1 &
    else
        # 修正: 原链接是 FreeBSD 版，会导致你的 Linux VPS 报错，此处修正为 Linux 版
        mtg_url="https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-amd64.tar.gz"
        wget -q -O mtg.tar.gz "$mtg_url"
        tar -xzf mtg.tar.gz
        mv mtg-*-linux-*/mtg "${WORKDIR}/mtg"
        rm -rf mtg.tar.gz mtg-*-linux-*

        if [ -e "${WORKDIR}/mtg" ]; then
            cd ${WORKDIR} && chmod +x mtg
            # 修正: 新版 mtg 使用 simple-run 命令
            nohup ./mtg simple-run -n 0.0.0.0:$MTP_PORT $SECRET >/dev/null 2>&1 &
        fi        
    fi
}

generate_info() {
    purple "\n分享链接:\n"
    LINKS=""
    [[ -n "$IP1" ]] && LINKS+="tg://proxy?server=$IP1&port=$MTP_PORT&secret=$SECRET"
    [[ -n "$IP2" ]] && LINKS+="\n\ntg://proxy?server=$IP2&port=$MTP_PORT&secret=$SECRET"
    [[ -n "$IP3" ]] && LINKS+="\n\ntg://proxy?server=$IP3&port=$MTP_PORT&secret=$SECRET"

    green "$LINKS\n"
    echo -e "$LINKS" > link.txt

    cat > ${WORKDIR}/restart.sh <<EOF
#!/bin/bash
pkill mtg
cd ~ && cd ${WORKDIR}
nohup ./mtg simple-run -n 0.0.0.0:$MTP_PORT $SECRET >/dev/null 2>&1 &
EOF
    chmod +x ${WORKDIR}/restart.sh
}

download_mtg(){
    cmd=$(uname -m)
    if [ "$cmd" == "x86_64" ] || [ "$cmd" == "amd64" ] ; then
        arch="amd64"
        # 修正: 使用官方 Linux 源
        url="https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-amd64.tar.gz"
    elif [ "$cmd" == "aarch64" ] || [ "$cmd" == "arm64" ] ; then
        arch="arm64"    
        url="https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-arm64.tar.gz"
    else
        arch="amd64"
        url="https://github.com/9seconds/mtg/releases/download/v2.1.7/mtg-2.1.7-linux-amd64.tar.gz"
    fi

    # 修正解压逻辑
    wget -q -O mtg.tar.gz "$url"
    tar -xzf mtg.tar.gz
    mv mtg-*-linux-*/mtg "${WORKDIR}/mtg"
    rm -rf mtg.tar.gz mtg-*-linux-*

    export PORT=${PORT:-$(shuf -i 20000-60000 -n 1)}
    # 修正: 原脚本逻辑 MTP_PORT = PORT + 1，这里保持原样
    export MTP_PORT=$(($PORT + 1)) 

    if [ -e "${WORKDIR}/mtg" ]; then
        cd ${WORKDIR} && chmod +x mtg
        # 修正: 使用 simple-run 适配新版程序
        nohup ./mtg simple-run -n 0.0.0.0:$MTP_PORT $SECRET >/dev/null 2>&1 &
    fi
}

show_link(){
    ip=$(curl -s 4.ipw.cn)
    purple "\nTG分享链接(如获取的是ipv6,可自行将ipv6换成ipv4):\n"
    LINKS="tg://proxy?server=$ip&port=$MTP_PORT&secret=$SECRET"
    green "$LINKS\n"
    echo -e "$LINKS" > $WORKDIR/link.txt

    purple "\n一键卸载命令: rm -rf mtp && pkill mtg"
}

install(){
    purple "正在安装中,请稍等...\n"
    # 这里是原脚本的核心逻辑：判断是不是 Serv00
    if [[ "$HOSTNAME" =~ serv00.com|ct8.pl|useruno.com ]]; then
        check_port
        get_ip
        download_run
        generate_info
    else
        # 你的 VPS 会走这条路
        download_mtg
        show_link
    fi
}

install