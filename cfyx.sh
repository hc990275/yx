#!/bin/bash

INSTALL_PATH="/usr/local/bin/cfy"

# --- 安装/更新逻辑 ---
if [ "$0" != "$INSTALL_PATH" ]; then
    echo "正在安装/更新 [cfy 节点优选生成器]..."

    if [ "$(id -u)" -ne 0 ]; then
        echo "错误: 安装需要管理员权限。请使用 'curl ... | sudo bash' 或 'sudo bash <(curl ...)' 命令来运行。"
        exit 1
    fi
    
    # 智能判断执行模式 (管道 vs 文件)
    if [[ "$(basename "$0")" == "bash" || "$(basename "$0")" == "sh" || "$(basename "$0")" == "-bash" ]]; then
        cat /proc/self/fd/0 > "$INSTALL_PATH"
    else
        cp "$0" "$INSTALL_PATH"
    fi

    if [ $? -eq 0 ]; then
        chmod +x "$INSTALL_PATH"
        echo "✅ 安装成功! 您现在可以随时随地运行 'cfy' 命令。"
        echo "---"
        echo "首次运行..."
        exec "$INSTALL_PATH"
    else
        echo "❌ 安装失败, 请检查权限。"
        exit 1
    fi
    exit 0
fi

# --- 主程序 ---

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

check_deps() {
    for cmd in jq curl base64 grep sed mktemp shuf; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}错误: 命令 '$cmd' 未找到. 请先安装它 (apt install $cmd 或 yum install $cmd).${NC}"
            exit 1
        fi
    done
}

get_github_ips() {
    # 优选 IP 源地址 (3.txt)
    local url="https://raw.githubusercontent.com/hc990275/yx/main/3.txt"
    
    echo -e "${YELLOW}正在从 GitHub 获取优选 IP 列表...${NC}"
    echo -e "  -> 源地址: $url"
    
    # 下载并处理：去除回车符，去除空行
    local raw_content
    raw_content=$(curl -s "$url" | tr -d '\r' | sed '/^$/d')
    
    if [ -z "$raw_content" ]; then
        echo -e "${RED}错误: 无法获取 IP 列表或列表为空，请检查网络连接。${NC}"
        return 1
    fi

    # 将内容读入数组
    declare -g -a ip_list
    mapfile -t ip_list <<< "$raw_content"

    if [ ${#ip_list[@]} -eq 0 ]; then
        echo -e "${RED}错误: 解析后未发现有效 IP。${NC}"
        return 1
    fi

    # 随机打乱数组，保证每次生成的节点顺序不一样
    local temp_file=$(mktemp)
    for ip in "${ip_list[@]}"; do echo "$ip" >> "$temp_file"; done
    mapfile -t ip_list < <(shuf "$temp_file")
    rm -f "$temp_file"

    echo -e "${GREEN}成功获取并随机排序 ${#ip_list[@]} 个优选 IP 地址。${NC}"
    return 0
}

main() {
    local url_file="/etc/sing-box/url.txt"
    declare -a valid_urls valid_ps_names
    
    echo -e "${GREEN}=================================================="
    echo -e " 节点优选生成器 (Custom For You)"
    echo -e " 模式: 自动全量 (GitHub 源)"
    echo -e "==================================================${NC}"
    echo ""

    # 1. 获取种子节点
    if [ -f "$url_file" ]; then
        mapfile -t urls < "$url_file"
        for url in "${urls[@]}"; do
            decoded_json=$(echo "${url#"vmess://"}" | base64 -d 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$decoded_json" ]; then
                ps=$(echo "$decoded_json" | jq -r .ps 2>/dev/null)
                if [ $? -eq 0 ] && [ -n "$ps" ]; then valid_urls+=("$url"); valid_ps_names+=("$ps"); fi
            fi
        done
    fi

    local selected_url
    if [ ${#valid_urls[@]} -gt 0 ]; then
        if [ ${#valid_urls[@]} -eq 1 ]; then
            selected_url=${valid_urls[0]}
            echo -e "${YELLOW}检测到只有一个有效节点, 已自动选择: ${valid_ps_names[0]}${NC}"
        else
            echo -e "${YELLOW}请选择一个节点作为模板:${NC}"
            for i in "${!valid_ps_names[@]}"; do printf "%3d) %s\n" "$((i+1))" "${valid_ps_names[$i]}"; done
            local choice
            while true; do
                read -p "请输入选项编号 (1-${#valid_urls[@]}): " choice
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#valid_urls[@]} ]; then
                    selected_url=${valid_urls[$((choice-1))]}; break
                else echo -e "${RED}无效输入.${NC}"; fi
            done
        fi
    else
        echo -e "${YELLOW}在 $url_file 中未找到有效节点.${NC}"
        while true; do
            read -p "请手动粘贴一个 vmess:// 链接: " selected_url
            if [[ "$selected_url" != vmess://* ]]; then echo -e "${RED}格式错误.${NC}"; continue; fi
            break
        done
    fi

    # 解码原始节点
    local base64_part=${selected_url#"vmess://"}
    local original_json=$(echo "$base64_part" | base64 -d)
    local original_ps=$(echo "$original_json" | jq -r .ps)
    # echo -e "${GREEN}已选择模板: $original_ps${NC}" # 既然自动了，这句也可以省略，或者保留作为提示

    # 2. 获取 IP 列表 (强制使用 GitHub 模式)
    get_github_ips || exit 1

    # 3. 确定生成数量 (强制全部)
    local num_to_generate=${#ip_list[@]}
    echo -e "${YELLOW}正在自动生成全部 $num_to_generate 个节点...${NC}"

    # 4. 生成新链接
    echo "---"
    echo -e "${YELLOW}=== 生成结果 ===${NC}"
    
    for ((i=0; i<$num_to_generate; i++)); do
        local current_ip=${ip_list[$i]}
        
        # 构造新名字: 原名-IP
        local new_ps="${original_ps}-${current_ip}"
        
        # 修改 JSON (替换 add 和 ps)
        local modified_json=$(echo "$original_json" | jq --arg new_add "$current_ip" --arg new_ps "$new_ps" '.add = $new_add | .ps = $new_ps')
        
        # 编码并输出
        local new_base64=$(echo -n "$modified_json" | base64 | tr -d '\n')
        echo "vmess://${new_base64}"
    done
    
    echo "---"
    echo -e "${GREEN}生成完毕! 已自动生成 $num_to_generate 个链接.${NC}"
}

check_deps
main
