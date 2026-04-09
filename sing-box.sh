bash -c '
# 1. 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   echo "请使用 root 权限运行此脚本"
   exit 1
fi

echo "=========================================="
echo "      正在开始环境检测与安装依赖"
echo "=========================================="

# 2. 定义需要安装的依赖 (命令:软件包)
DEPS=("jq:jq" "iptables:iptables" "ifconfig:net-tools" "curl:curl")

# 3. 检测系统类型并配置包管理器
if command -v apk &> /dev/null; then
    echo "检测到系统为 Alpine Linux，正在更新包列表..."
    apk update
    INSTALL_CMD="apk add"
elif command -v apt &> /dev/null; then
    echo "检测到系统为 Debian/Ubuntu，正在更新包列表..."
    apt update -y
    INSTALL_CMD="apt install -y"
else
    echo "不支持的系统或找不到 apt/apk 包管理器！"
    exit 1
fi

# 4. 检查并安装依赖
for item in "${DEPS[@]}"; do
    CMD=${item%%:*}
    PKG=${item#*:}
    if ! command -v "$CMD" &> /dev/null; then
        echo "--> 缺少组件 $CMD，正在安装 $PKG..."
        $INSTALL_CMD "$PKG"
    else
        echo "[OK] 组件 $CMD 已安装"
    fi
done

echo "=========================================="
echo "    所有环境依赖已就绪，正在启动工具箱"
echo "=========================================="
sleep 1

# 5. 启动 SSH 工具箱
bash <(curl -Ls ssh_tool.eooce.com)
'
