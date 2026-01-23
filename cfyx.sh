#!/bin/bash

# ==================================================
#   TG@sddzn 节点优选生成器 (全量版)
# ==================================================

INSTALL_PATH="/usr/local/bin/cfy"

# --- 安装/更新逻辑 ---
if [ "$0" != "$INSTALL_PATH" ]; then
    echo "正在安装/更新 [TG@sddzn 节点优选生成器]..."
    
    if [ "$(id -u)" -ne 0 ]; then
        echo "错误: 需要管理员权限。请使用 sudo。"
        exit 1
    fi

    if [[ "$(basename "$0")" == "bash" || "$(basename "$0")" == "sh" ]]; then
        cat /proc/self/fd/0 > "$INSTALL_PATH"
    else
        cp "$0" "$INSTALL_PATH"
    fi

    chmod +x "$INSTALL_PATH"
    echo "✅ 安装成功! 输入 'cfy' 即可运行。"
    echo "---"
    exec "$INSTALL_PATH"
    exit 0
fi

# --- 主程序 ---

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 依赖检查
check_deps() {
    for cmd in jq curl base64 grep sed; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}错误: 缺少命令 '$cmd'。请先安装 (apt/yum install $cmd)。${NC}"
            exit 1
        fi
    done
}

# 获取 GitHub IP (核心逻辑修改：直接取全部，去重空行)
get_github_ips() {
    # 直接在此处定义，防止变量丢失
    local url="https://raw.githubusercontent.com/hc990275/yx/main/3.txt"
    
    echo -e "${YELLOW}正在从 GitHub 拉取优选 IP 列表...${NC}"
    echo -e "  -> 源地址: $url"
    
    # 增加 -L 参数以支持重定向，增加超时设置
    # tr -d '\r' 去除 Windows 回车符
    # sed '/^$/d' 去除空行
    local raw_content
    raw_content=$(curl -L -s --max-time 10 "$url" | tr -d '\r' | sed '/^$/d')
    
    if [ -z "$raw_content" ]; then
        echo -e "${RED}错误: 获取失败！内容为空或网络不通。${NC}"
        echo -e "${RED}请检查服务器是否能访问 GitHub (raw.githubusercontent.com)。${NC}"
        return 1
    fi

    # 读入全局数组
    declare -g -a ip_list
    mapfile -t ip_list <<< "$raw_content"

    if [ ${#ip_list[@]} -eq 0 ]; then
        echo -e "${RED}错误: 文件中未发现有效 IP。${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ 成功获取 ${#ip_list[@]} 个 IP 地址。${NC}"
    return 0
}

main() {
    local url_file="/etc/sing-box/url.txt"
    declare -a valid_urls valid_ps_names
    
    echo -e "${GREEN}=================================================="
    echo -e "      TG@sddzn 节点优选生成器 (批量全量版)"
    echo -e "==================================================${NC}"

    # 1. 获取种子节点
    if [ -f "$url_file" ]; then
        mapfile -t urls < "$url_file"
        for url in "${urls[@]}"; do
            decoded_json=$(echo "${url#"vmess://"}" | base64 -d 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$decoded_json" ]; then
                ps=$(echo "$decoded_json" | jq -r .ps 2>/dev/null)
                if [ -n "$ps" ]; then 
                    valid_urls+=("$url"); valid_ps_names+=("$ps")
                fi
            fi
        done
    fi

    local selected_url
    if [ ${#valid_urls[@]} -gt 0 ]; then
        if [ ${#valid_urls[@]} -eq 1 ]; then
            selected_url=${valid_urls[0]}
            echo -e "${YELLOW}使用模板: ${valid_ps_names[0]}${NC}"
        else
            echo -e "${YELLOW}请选择模板节点:${NC}"
            for i in "${!valid_ps_names[@]}"; do 
                printf "%3d) %s\n" "$((i+1))" "${valid_ps_names[$i]}"
            done
            read -p "请输入编号: " choice
            selected_url=${valid_urls[$((choice-1))]}
        fi
    else
        echo -e "${YELLOW}未找到配置文件，请手动输入 vmess:// 链接:${NC}"
        read selected_url
    fi

    # 解码模板
    local base64_part=${selected_url#"vmess://"}
    local original_json=$(echo "$base64_part" | base64 -d)
    local original_ps=$(echo "$original_json" | jq -r .ps)
    
    # 2. 直接执行获取 IP (不再询问来源)
    get_github_ips || exit 1
    
    # 3. 直接使用全部数量 (不再询问数量)
    local num_to_generate=${#ip_list[@]}
    
    echo "---"
    echo -e "${YELLOW}正在生成全部 $num_to_generate 个节点...${NC}"
    
    for ((i=0; i<$num_to_generate; i++)); do
        local current_ip=${ip_list[$i]}
        
        # 命名格式: 原始名_TG@sddzn_IP
        local new_ps="${original_ps}_TG@sddzn_${current_ip}"
        
        # 替换 IP 和 名字
        local modified_json=$(echo "$original_json" | jq --arg ip "$current_ip" --arg ps "$new_ps" '.add = $ip | .ps = $ps')
        
        # Base64 编码 (不换行)
        local new_base64=$(echo -n "$modified_json" | base64 | tr -d '\n')
        echo "vmess://${new_base64}"
    done
    
    echo "---"
    echo -e "${GREEN}完成! 共生成 $num_to_generate 个节点。${NC}"
}

check_deps
main
