#!/bin/bash

# 检查是否以 root 权限运行
if [[ $EUID -ne 0 ]]; then
   echo "请使用 root 权限运行此脚本 (sudo -i)"
   exit 1
fi

echo "正在开始环境检测与安装..."

# 1. 更新软件包列表
echo "正在执行 apt update..."
apt update -y

# 2. 定义需要检测的命令列表
# 格式为: "命令名称:安装包名称"
DEPS=("jq:jq" "iptables:iptables" "ifconfig:net-tools")

for item in "${DEPS[@]}"; do
    CMD=${item%%:*}
    PKG=${item#*:}

    # 检查命令是否存在
    if ! command -v "$CMD" &> /dev/null; then
        echo "检测到缺失 $CMD，正在安装 $PKG..."
        apt install "$PKG" -y
    else
        echo "[OK] $CMD 已安装"
    fi
done

echo "-----------------------------------------------"
echo "所有前置依赖已就绪！"
echo "正在启动 sing-box 安装脚本..."
echo "-----------------------------------------------"

# 3. 自动执行你的目标脚本
bash <(curl -Ls https://raw.githubusercontent.com/eooce/sing-box/main/sing-box.sh)
