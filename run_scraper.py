import os
import re
import requests
from bs4 import BeautifulSoup
import datetime

URL = os.environ.get("VPN_SOURCE_URL")
FILE_NAME = "家宽/非219IP.md"

def get_new_data():
    """抓取网页并提取非219开头的行"""
    headers = {"User-Agent": "Mozilla/5.0"}
    try:
        print(f"正在抓取: {URL}")
        resp = requests.get(URL, headers=headers, timeout=30)
        resp.encoding = resp.apparent_encoding # 防止乱码
        
        # 使用 BeautifulSoup 获取纯文本行，保留排版
        soup = BeautifulSoup(resp.text, 'html.parser')
        # 获取网页上的所有文本内容，按行分割
        text_lines = soup.get_text(separator="\n").splitlines()
        
        valid_lines = []
        # 正则匹配 IP 地址: x.x.x.x
        ip_pattern = re.compile(r'\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b')

        for line in text_lines:
            line = line.strip()
            match = ip_pattern.search(line)
            if match:
                ip = match.group(1)
                # --- 核心规则：排除 219 开头的 IP ---
                if not ip.startswith("219."):
                    # 简单的清洗：去掉可能存在的 Markdown 表格符，防止重复
                    clean_line = line.replace("|", "").strip()
                    if clean_line:
                        # 重新格式化为表格行
                        valid_lines.append(f"| {clean_line} |")
        return valid_lines
    except Exception as e:
        print(f"抓取失败: {e}")
        return []

def load_old_data():
    """读取现有的 MD 文件中的数据行"""
    if not os.path.exists(FILE_NAME):
        return []
    
    old_lines = []
    with open(FILE_NAME, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            # 只读取以 "| 数字" 开头的行，忽略表头和空行
            if line.startswith("|") and re.search(r'\|\s*\d', line):
                old_lines.append(line)
    return old_lines

def main():
    # 1. 确保目录存在
    os.makedirs("家宽", exist_ok=True)

    # 2. 获取数据
    new_data = get_new_data()
    old_data = load_old_data()
    
    print(f"新抓取数据: {len(new_data)} 条")
    print(f"历史数据: {len(old_data)} 条")

    if not new_data:
        print("本次未抓取到有效数据，结束。")
        return

    # 3. 合并与去重 (核心逻辑)
    # 顺序：新数据在前 + 旧数据在后
    combined_data = new_data + old_data
    
    seen = set()
    unique_data = []
    for item in combined_data:
        # 以行内容作为去重依据
        if item not in seen:
            seen.add(item)
            unique_data.append(item)
    
    print(f"合并去重后总数据: {len(unique_data)} 条")

    # 4. 写入文件
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    with open(FILE_NAME, "w", encoding="utf-8") as f:
        f.write(f"# 非 219 IP 永久记录库\n\n")
        f.write(f"> 最后更新: {timestamp} | 总数: {len(unique_data)}\n\n")
        f.write(f"| IP / 端口 / 地区信息 |\n")
        f.write(f"| :--- |\n")
        for line in unique_data:
            f.write(f"{line}\n")
    
    print("文件更新成功！")

if __name__ == "__main__":
    main()
