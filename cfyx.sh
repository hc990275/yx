#!/bin/bash

# ==================================================
#   TG@sddzn 节点优选生成器 (最终修复版)
# ==================================================

INSTALL_PATH="/usr/local/bin/cfy"

# --- 1. 安装与自更新逻辑 ---
if [ "$0" != "$INSTALL_PATH" ]; then
    echo "正在安装/更新 [TG@sddzn 节点优选生成器]..."
    
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ 错误: 需要管理员权限。请使用 'sudo bash ...' 运行。"
        exit 1
    fi

    # 写入文件
    if [[ "$(basename "$0")" == "bash" || "$(basename "$0")" == "sh" ]]; then
        cat /proc/self/fd/0 > "$INSTALL_PATH"
    else
        cp "$0" "$INSTALL_PATH"
    fi

    chmod +x "$INSTALL_PATH"
    echo "✅ 安装成功! 输入 'cfy' 即可直接运行。"
    echo "---"
    exec "$INSTALL_PATH"
    exit 0
fi

# --- 2. 核心程序 ---

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

check_deps() {
    for cmd in jq curl base64 grep sed; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}❌ 错误: 缺少命令 '$cmd'。请先安装它 (apt install $cmd)。${NC}"
            exit 1
        fi
    done
}

# 获取 GitHub IP (修复变量作用域问题)
get_github_ips() {
    # --- 关键修复：URL直接定义在函数内 ---
    local url="https://raw.githubusercontent.com/hc990275/yx/main/yxip.txt"
    # ----------------------------------
    
    echo -e "${YELLOW}正在从 GitHub 拉取优选 IP 列表...${NC}"
    echo -e "  -> 目标地址: $url"
    
    # -L 跟随重定向, --max-time 设置超时
    local raw_content
    raw_content=$(curl -s -L --max-time 15 "$url" | tr -d '\r' | sed '/^$/d')
    
    if [ -z "$raw_content" ]; then
        echo -e "${RED}❌ 获取失败！内容为空或连接超时。${NC}"
        echo -e "${RED}   请检查服务器是否能访问 GitHub。${NC}"
        return 1
    fi

    # 存入全局数组
    declare -g -a ip_list
    mapfile -t ip_list <<< "$raw_content"

    local count=${#ip_list[@]}
    if [ "$count" -eq 0 ]; then
        echo -e "${RED}❌ 解析失败: 未发现有效 IP。${NC}"
        return 1
    fi

    echo -e "${GREEN}✅ 成功获取 $count 个 IP 地址。${NC}"
    return 0
}

main() {
    local url_file="/etc/sing-box/url.txt"
    declare -a valid_urls valid_ps_names
    
    echo -e "${GREEN}=================================================="
    echo -e "      TG@sddzn 节点优选生成器 (自动版)"
    echo -e "==================================================${NC}"

    # --- 步骤 1: 读取本地种子节点 ---
    if [ -f "$url_file" ]; then
        while IFS= read -r url || [ -n "$url" ]; do
            if [[ "$url" == vmess://* ]]; then
                decoded_json=$(echo "${url#"vmess://"}" | base64 -d 2>/dev/null)
                if [ $? -eq 0 ] && [ -n "$decoded_json" ]; then
                    ps=$(echo "$decoded_json" | jq -r .ps 2>/dev/null)
                    if [ -n "$ps" ]; then 
                        valid_urls+=("$url"); valid_ps_names+=("$ps")
                    fi
                fi
            fi
        done < "$url_file"
    fi

    local selected_url
    if [ ${#valid_urls[@]} -gt 0 ]; then
        if [ ${#valid_urls[@]} -eq 1 ]; then
            selected_url=${valid_urls[0]}
            echo -e "${YELLOW}自动使用唯一模板: ${valid_ps_names[0]}${NC}"
        else
            # 如果有多个，还是得选一下，不然不知道用哪个做模板
            echo -e "${YELLOW}请选择模板节点:${NC}"
            for i in "${!valid_ps_names[@]}"; do 
                printf "%3d) %s\n" "$((i+1))" "${valid_ps_names[$i]}"
            done
            local choice
            read -p "请输入编号: " choice
            selected_url=${valid_urls[$((choice-1))]}
        fi
    else
        echo -e "${YELLOW}未找到配置文件，请手动输入 vmess:// 链接:${NC}"
        read selected_url
    fi

    # 解码原始数据
    local base64_part=${selected_url#"vmess://"}
    local original_json=$(echo "$base64_part" | base64 -d)
    
    # --- 步骤 2: 获取 IP (不询问，直接跑) ---
    get_github_ips || exit 1
    
    local num_to_generate=${#ip_list[@]}
    
    echo "---"
    echo -e "${YELLOW}正在生成全部 $num_to_generate 个配置...${NC}"
    
    for ((i=0; i<$num_to_generate; i++)); do
        local current_ip=${ip_list[$i]}
        
        # -----------------------------------------------------------
        # 修改点：别名格式设置
        # 格式: TG@sddzn-IP地址
        # (必须要带IP，否则生成的节点名字全部一样，会被软件当成重复节点覆盖掉)
        # -----------------------------------------------------------
        local new_ps="TG@sddzn-${current_ip}"
        
        if [ -n "$current_ip" ]; then
            # 修改 IP(add) 和 别名(ps)
            local modified_json=$(echo "$original_json" | jq --arg ip "$current_ip" --arg ps "$new_ps" '.add = $ip | .ps = $ps' -c)
            
            # Base64 编码输出
            local new_base64=$(echo -n "$modified_json" | base64 | tr -d '\n')
            echo "vmess://${new_base64}"
        fi
    done
    
    echo "---"
    echo -e "${GREEN}完成! 节点别名统一为: TG@sddzn-IP${NC}"
}

check_deps
main
