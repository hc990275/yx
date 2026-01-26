import os
import requests
from bs4 import BeautifulSoup
import datetime
import re

# 从环境变量获取 URL，如果本地运行则使用默认值
TARGET_URL = os.getenv('TARGET_URL', 'https://ipspeed.info/free-l2tpipsec.php')

# 国家名称映射 (英文 -> 简体中文)
COUNTRY_MAP = {
    "Japan": "日本",
    "Republic of Korea": "韩国",
    "United States": "美国",
    "United Kingdom": "英国",
    "Germany": "德国",
    "France": "法国",
    "Netherlands": "荷兰",
    "Singapore": "新加坡",
    "Canada": "加拿大",
    "Russia": "俄罗斯",
    "India": "印度",
    "Australia": "澳大利亚",
    "China": "中国",
    "Hong Kong": "中国香港",
    "Taiwan": "中国台湾",
    "Brazil": "巴西",
    "Vietnam": "越南",
    "Thailand": "泰国",
    "Indonesia": "印度尼西亚",
    "Turkey": "土耳其"
}

def translate_country(english_name):
    """将英文国家名转换为中文"""
    clean_name = english_name.strip()
    return COUNTRY_MAP.get(clean_name, clean_name)

def parse_uptime_to_minutes(uptime_str):
    """
    将在线时间字符串 (e.g., '60 days', '0 mins', '2 hours') 转换为分钟数用于排序。
    """
    uptime_str = uptime_str.lower().strip()
    
    # 提取数字
    match = re.search(r'(\d+)', uptime_str)
    if not match:
        return float('inf') # 无法解析则放到最后
    
    value = int(match.group(1))
    
    if 'day' in uptime_str:
        return value * 24 * 60
    elif 'hour' in uptime_str:
        return value * 60
    elif 'min' in uptime_str:
        return value
    elif 'sec' in uptime_str:
        return 0 # 秒级视为0分钟
    
    return value

def scrape_and_generate_readme():
    print(f"正在抓取: {TARGET_URL}")
    
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
    }

    try:
        response = requests.get(TARGET_URL, headers=headers, timeout=20)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'html.parser')
    except Exception as e:
        print(f"请求失败: {e}")
        return

    # 定位表格
    table = soup.find('table', class_='table table-success table-striped text-nowrap')
    if not table:
        print("错误: 未找到目标表格。")
        return

    vpn_nodes = []
    
    tbody = table.find('tbody')
    rows = tbody.find_all('tr') if tbody else []

    for row in rows:
        cols = row.find_all('td')
        # 表格结构: # (th), Location (td), IP (td), Uptime (td), Ping (td)
        if len(cols) >= 4:
            location_raw = cols[0].get_text(strip=True)
            ip_address = cols[1].get_text(strip=True)
            uptime_str = cols[2].get_text(strip=True)
            ping = cols[3].get_text(strip=True)

            location_cn = translate_country(location_raw)
            uptime_minutes = parse_uptime_to_minutes(uptime_str)

            vpn_nodes.append({
                "location": location_cn,
                "ip": ip_address,
                "uptime_str": uptime_str,
                "uptime_minutes": uptime_minutes, # 用于排序
                "ping": ping
            })

    # 核心逻辑：按照运行时间排序（从小到大，短的在上面）
    vpn_nodes.sort(key=lambda x: x['uptime_minutes'])

    # 生成 Markdown 内容
    current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    md_content = f"# 家宽 L2TP/IPsec VPN 列表\n\n"
    md_content += f"> 更新时间: {current_time} (UTC+0)\n"
    md_content += f"> 数据来源: [{TARGET_URL}]({TARGET_URL})\n\n"
    md_content += f"**排序规则**：按在线时间倒序（新上线的节点在最上方）。\n\n"
    
    md_content += "| 地区 | IP 地址 | 在线时间 | 延迟 (Ping) |\n"
    md_content += "| :--- | :--- | :--- | :--- |\n"

    for node in vpn_nodes:
        # 加粗显示运行时间少于 1 天 (1440分钟) 的节点
        uptime_display = node['uptime_str']
        if node['uptime_minutes'] < 1440:
            uptime_display = f"**{uptime_display}** 🆕"

        md_content += f"| {node['location']} | `{node['ip']}` | {uptime_display} | {node['ping']} |\n"

    # 获取脚本所在目录，确保 README 生成在 '家宽' 目录下
    script_dir = os.path.dirname(os.path.abspath(__file__))
    readme_path = os.path.join(script_dir, 'README.md')

    with open(readme_path, 'w', encoding='utf-8') as f:
        f.write(md_content)

    print(f"成功生成 README.md，共 {len(vpn_nodes)} 个节点。")

if __name__ == "__main__":
    scrape_and_generate_readme()
