#!/bin/bash

# ==================================================
#    TG@sddzn 节点优选生成器 (GitHub Actions 专用版)
# ==================================================

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- 1. 依赖检查 ---
check_deps() {
    # 注意：GitHub Actions 运行器通常自带 base64, grep, sed
    for cmd in jq curl base64 grep sed; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}❌ 错误: 缺少命令 '$cmd'。${NC}"
            exit 1
        fi
    done
}

# --- 2. 获取 GitHub 优选 IP ---
get_github_ips() {
    local url="https://raw.githubusercontent.com/hc990275/yx/main/50%E4%B8%AAIP.txt"
    
    echo -e "${YELLOW}正在从 GitHub 拉取 50 个优选 IP 列表...${NC}"
    
    # 获取内容并清理格式 (移除回车符和空行)
    local raw_content
    raw_content=$(curl -s -L --max-time 15 "$url" | tr -d '\r' | sed '/^$/d')
    
    if [ -z "$raw_content" ]; then
        echo -e "${RED}❌ 获取失败！内容为空或连接超时。${NC}"
        return 1
    fi

    # 将内容读入全局数组 ip_list
    declare -g -a ip_list
    mapfile -t ip_list <<< "$raw_content"

    local count=${#ip_list[@]}
    echo -e "${GREEN}✅ 成功获取 $count 个 IP 地址。${NC}"
    return 0
}

# --- 3. 主程序逻辑 ---
main() {
    local url_file="/etc/sing-box/url.txt"
    declare -a valid_urls valid_ps_names
    
    echo -e "${GREEN}=================================================="
    echo -e "      TG@sddzn 节点生成 (自动化模式)"
    echo -e "==================================================${NC}"

    # 3.1 读取本地模板文件
    if [ -f "$url_file" ]; then
        echo -e "${YELLOW}正在读取模板文件: $url_file ...${NC}"
        while IFS= read -r url || [ -n "$url" ]; do
            # 简单清洗空白字符
            url=$(echo "$url" | tr -d '[:space:]')
            
            if [[ "$url" == vmess://* ]]; then
                # 解码验证
                decoded_json=$(echo "${url#"vmess://"}" | base64 -d 2>/dev/null)
                if [ $? -eq 0 ] && [ -n "$decoded_json" ]; then
                    ps=$(echo "$decoded_json" | jq -r .ps 2>/dev/null)
                    if [ -n "$ps" ]; then 
                        valid_urls+=("$url")
                        valid_ps_names+=("$ps")
                    fi
                fi
            fi
        done < "$url_file"
    else
        echo -e "${RED}❌ 错误: 找不到模板文件 $url_file${NC}"
        exit 1
    fi

    # 3.2 自动选择模板 (关键修改：移除交互，默认为第一个)
    local selected_url
    if [ ${#valid_urls[@]} -gt 0 ]; then
        # 直接选择第一个有效的节点作为模板
        selected_url=${valid_urls[0]}
        echo -e "${GREEN}✅ 自动化模式：已默认选择第一个模板节点 [${valid_ps_names[0]}]${NC}"
    else
        echo -e "${RED}❌ 错误: 模板文件中没有找到有效的 vmess 链接。${NC}"
        exit 1
    fi

    # 3.3 解析模板 JSON
    local base64_part=${selected_url#"vmess://"}
    local original_json=$(echo "$base64_part" | base64 -d)
    
    # 3.4 获取 IP 列表
    get_github_ips || exit 1
    
    local num_to_generate=${#ip_list[@]}
    echo "---"
    echo -e "${YELLOW}正在生成 $num_to_generate 个配置节点...${NC}"
    
    # 3.5 循环生成新节点
    for ((i=0; i<$num_to_generate; i++)); do
        local current_ip=${ip_list[$i]}
        
        # 设定别名为 TG@sddzn-IP
        local new_ps="TG@sddzn-${current_ip}"
        
        if [ -n "$current_ip" ]; then
            # 使用 jq 修改 add (地址) 和 ps (别名)
            # 注意：-c 参数让输出变为紧凑的单行 JSON
            local modified_json=$(echo "$original_json" | jq --arg ip "$current_ip" --arg ps "$new_ps" '.add = $ip | .ps = $ps' -c)
            
            # Base64 编码并输出
            local new_base64=$(echo -n "$modified_json" | base64 | tr -d '\n')
            echo "vmess://${new_base64}"
        fi
    done
    
    echo "" # 输出一个换行，防止文件末尾无换行
    echo "---"
    echo -e "${GREEN}处理完成。${NC}"
}

# 执行
check_deps
main
