#!/bin/bash

# =========================================================
# 脚本名称: MTProto Proxy 一键安装脚本
# 功能描述: 
#   1. 检查 Root 权限
#   2. 接受用户自定义端口
#   3. 随机生成 32位 16进制密钥
#   4. 下载并配置 mtg (Go版 MTProto 代理)
#   5. 配置 Systemd 实现后台运行和开机自启
#   6. 输出 Telegram 连接链接
# =========================================================

# 定义颜色变量，用于输出美观
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 1. 检查是否为 Root 用户
# ---------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 请使用 root 用户运行此脚本。${PLAIN}"
    echo -e "尝试命令: sudo -i 切换到 root 用户"
    exit 1
fi

echo -e "${GREEN}>>> 正在初始化环境...${PLAIN}"

# 2. 安装基础依赖 (curl, wget, tar)
# ---------------------------------------------------------
if [ -f /etc/debian_version ]; then
    apt-get update -y
    apt-get install -y curl wget tar
elif [ -f /etc/redhat-release ]; then
    yum update -y
    yum install -y curl wget tar
fi

# 3. 获取用户输入的端口
# ---------------------------------------------------------
echo "------------------------------------------------"
read -p "请输入你要开放的代理端口 (例如 443, 8443): " PROXY_PORT

# 简单验证端口是否为数字
if ! [[ "$PROXY_PORT" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}错误: 端口必须是数字。${PLAIN}"
    exit 1
fi

echo -e "${GREEN}>>> 已选择端口: ${PROXY_PORT}${PLAIN}"

# 4. 随机生成密钥 (Secret)
# ---------------------------------------------------------
# 使用 openssl 生成 16字节(32字符) 的随机十六进制字符串
# 这种密钥格式是标准的 MTProto 密钥
PROXY_SECRET=$(head -c 16 /dev/urandom | xxd -ps)

echo -e "${GREEN}>>> 已生成随机密钥: ${PROXY_SECRET}${PLAIN}"

# 5. 下载并安装 mtg (Go版 MTProto)
# ---------------------------------------------------------
# 这里使用的是 9seconds/mtg 的稳定版本，如果需要最新版可自行替换链接
# 为了脚本稳定性，我们通过检测架构下载对应版本

ARCH=$(uname -m)
MTG_VERSION="2.1.7" # 指定一个稳定版本
DOWNLOAD_URL=""

echo -e "${GREEN}>>> 正在检测系统架构...${PLAIN}"

if [[ "$ARCH" == "x86_64" ]]; then
    DOWNLOAD_URL="https://github.com/9seconds/mtg/releases/download/v${MTG_VERSION}/mtg-${MTG_VERSION}-linux-amd64.tar.gz"
elif [[ "$ARCH" == "aarch64" ]]; then
    DOWNLOAD_URL="https://github.com/9seconds/mtg/releases/download/v${MTG_VERSION}/mtg-${MTG_VERSION}-linux-arm64.tar.gz"
else
    echo -e "${RED}错误: 不支持的架构 $ARCH${PLAIN}"
    exit 1
fi

echo -e "${GREEN}>>> 正在下载主程序...${PLAIN}"
wget -O mtg.tar.gz "$DOWNLOAD_URL"

if [[ $? -ne 0 ]]; then
    echo -e "${RED}错误: 下载失败，请检查网络连接。${PLAIN}"
    exit 1
fi

# 解压并移动二进制文件
echo -e "${GREEN}>>> 正在安装...${PLAIN}"
tar -xzvf mtg.tar.gz
# 移动解压出来的目录中的 mtg 文件到 /usr/local/bin
# 注意：解压后的文件夹名称包含版本号
mv mtg-${MTG_VERSION}-linux-*/mtg /usr/local/bin/mtg
chmod +x /usr/local/bin/mtg

# 清理临时文件
rm -rf mtg.tar.gz mtg-${MTG_VERSION}-linux-*

# 6. 配置 Systemd 服务 (后台保活)
# ---------------------------------------------------------
echo -e "${GREEN}>>> 正在配置 Systemd 服务...${PLAIN}"

# 写入服务文件
cat <<EOF > /etc/systemd/system/mtg.service
[Unit]
Description=MTProto Proxy Service (Go Version)
After=network.target

[Service]
Type=simple
# 简单的运行模式：监听 0.0.0.0:端口 并使用生成的密钥
ExecStart=/usr/local/bin/mtg simple-run -n 0.0.0.0:${PROXY_PORT} ${PROXY_SECRET}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 重载 Systemd 并启动服务
systemctl daemon-reload
systemctl enable mtg
systemctl start mtg

# 检查服务状态
if systemctl is-active --quiet mtg; then
    echo -e "${GREEN}>>> MTProto 代理已成功启动！${PLAIN}"
else
    echo -e "${RED}错误: 服务启动失败，请检查日志 (journalctl -u mtg)${PLAIN}"
    exit 1
fi

# 7. 配置防火墙 (简单处理)
# ---------------------------------------------------------
# 尝试放行端口，兼容 ufw 和 iptables
echo -e "${GREEN}>>> 正在尝试配置防火墙端口...${PLAIN}"

if command -v ufw > /dev/null; then
    ufw allow "$PROXY_PORT"/tcp
    ufw allow "$PROXY_PORT"/udp
    echo "UFW 规则已添加"
fi

if command -v iptables > /dev/null; then
    iptables -I INPUT -p tcp --dport "$PROXY_PORT" -j ACCEPT
    iptables -I INPUT -p udp --dport "$PROXY_PORT" -j ACCEPT
    # 简单的保存尝试，不一定适用于所有系统
    # iptables-save > /etc/iptables/rules.v4 2>/dev/null
    echo "Iptables 规则已尝试添加 (重启可能失效，请根据系统自行持久化)"
fi

# 8. 输出连接信息
# ---------------------------------------------------------
# 获取公网 IP
PUBLIC_IP=$(curl -s 4.ipw.cn)
if [[ -z "$PUBLIC_IP" ]]; then
    PUBLIC_IP="YOUR_VPS_IP"
fi

echo "========================================================"
echo -e "   ${GREEN}MTProto 代理安装完成！${PLAIN}"
echo "========================================================"
echo -e "服务器 IP  : ${YELLOW}${PUBLIC_IP}${PLAIN}"
echo -e "端口 (Port): ${YELLOW}${PROXY_PORT}${PLAIN}"
echo -e "密钥 (Secret): ${YELLOW}${PROXY_SECRET}${PLAIN}"
echo "--------------------------------------------------------"
echo -e "一键连接链接 (点击链接即可添加代理):"
echo -e "${GREEN}tg://proxy?server=${PUBLIC_IP}&port=${PROXY_PORT}&secret=${PROXY_SECRET}${PLAIN}"
echo "========================================================"