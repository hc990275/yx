#!/bin/bash

# =========================================================
# 脚本名称: MTProto Proxy (Python版) 一键安装脚本
# 适用系统: Ubuntu 20.04+, Debian 10+ (推荐 Ubuntu 24.04)
# 特点: 兼容性最好，解决 Go 版本无法运行的问题
# =========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查 Root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误: 请使用 root 用户运行此脚本。${PLAIN}"
    exit 1
fi

# =========================================================
# 1. 安装环境与依赖
# =========================================================
echo -e "${GREEN}>>> [1/5] 正在更新系统并安装 Python 环境...${PLAIN}"
# 为了兼容 Ubuntu 24.04 的 PEP 668 限制，我们优先使用 apt 安装 python 库
apt-get update -y
apt-get install -y git python3 python3-pip python3-cryptography python3-uvloop curl

# =========================================================
# 2. 配置参数
# =========================================================
echo -e "${GREEN}>>> [2/5] 配置代理参数...${PLAIN}"

# 设置端口
DEFAULT_PORT=$((RANDOM % 10000 + 20000))
read -p "请输入端口 (默认 $DEFAULT_PORT): " INPUT_PORT
PROXY_PORT=${INPUT_PORT:-$DEFAULT_PORT}

# 生成密钥 (Secret)
# Python 版通常生成 32 字符的 hex 密钥
PROXY_SECRET=$(head -c 16 /dev/urandom | xxd -ps)

echo -e "端口: $PROXY_PORT"
echo -e "密钥: $PROXY_SECRET"

# =========================================================
# 3. 下载源码 (使用 alexbers/mtprotoproxy 高性能异步版)
# =========================================================
echo -e "${GREEN}>>> [3/5] 拉取项目源码...${PLAIN}"

# 清理旧目录
rm -rf /opt/mtprotoproxy

# 克隆仓库
git clone https://github.com/alexbers/mtprotoproxy.git /opt/mtprotoproxy

if [ ! -d "/opt/mtprotoproxy" ]; then
    echo -e "${RED}错误: 源码下载失败，请检查 GitHub 连接。${PLAIN}"
    exit 1
fi

# =========================================================
# 4. 配置 Systemd 服务
# =========================================================
echo -e "${GREEN}>>> [4/5] 配置后台服务...${PLAIN}"

cat <<EOF > /etc/systemd/system/mtproto-py.service
[Unit]
Description=MTProto Proxy (Python Async)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/mtprotoproxy
# 启动命令: 指定端口和密钥
ExecStart=/usr/bin/python3 /opt/mtprotoproxy/mtprotoproxy.py -p ${PROXY_PORT} -s ${PROXY_SECRET}
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 重载并启动
systemctl daemon-reload
systemctl enable mtproto-py
systemctl restart mtproto-py

# =========================================================
# 5. 防火墙与状态检查
# =========================================================
echo -e "${GREEN}>>> [5/5] 检查运行状态...${PLAIN}"

# 简单放行端口
if command -v ufw > /dev/null; then
    ufw allow $PROXY_PORT/tcp
fi
if command -v iptables > /dev/null; then
    iptables -I INPUT -p tcp --dport $PROXY_PORT -j ACCEPT
fi

sleep 2

# 检查服务是否存活
if systemctl is-active --quiet mtproto-py; then
    PUBLIC_IP=$(curl -s 4.ipw.cn)
    [ -z "$PUBLIC_IP" ] && PUBLIC_IP="你的VPS_IP"

    echo "========================================================"
    echo -e "   ${GREEN}MTProto (Python版) 安装成功！${PLAIN}"
    echo "========================================================"
    echo -e "IP 地址: ${YELLOW}${PUBLIC_IP}${PLAIN}"
    echo -e "端口   : ${YELLOW}${PROXY_PORT}${PLAIN}"
    echo -e "密钥   : ${YELLOW}${PROXY_SECRET}${PLAIN}"
    echo "--------------------------------------------------------"
    echo -e "TG 一键链接:"
    echo -e "${GREEN}tg://proxy?server=${PUBLIC_IP}&port=${PROXY_PORT}&secret=${PROXY_SECRET}${PLAIN}"
    echo "========================================================"
    echo -e "${YELLOW}注意: 如果连不上，请务必去阿里云/腾讯云网页后台放行 ${PROXY_PORT} 端口！${PLAIN}"
else
    echo -e "${RED}服务启动失败。${PLAIN}"
    echo "请运行 journalctl -u mtproto-py -n 20 查看报错。"
fi