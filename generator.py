import base64
import json
import os
import requests
from datetime import datetime

def decode_vmess(vmess_str):
    if vmess_str.startswith("vmess://"):
        vmess_str = vmess_str[8:]
    padding = len(vmess_str) % 4
    if padding:
        vmess_str += "=" * (4 - padding)
    decoded = base64.b64decode(vmess_str).decode('utf-8')
    return json.loads(decoded)

def encode_vmess(vmess_obj):
    json_str = json.dumps(vmess_obj, indent=2)
    encoded = base64.b64encode(json_str.encode('utf-8')).decode('utf-8')
    return f"vmess://{encoded}"

def main():
    # 配置从环境变量读取
    target_regions = os.environ.get("TARGET_REGIONS", "AE,HK,US,JP").split(",")
    per_region_count = int(os.environ.get("PER_REGION_COUNT", "10"))
    ip_list_url = "https://raw.githubusercontent.com/hc990275/yx/main/cfyxip.txt"
    output_file = "deip.txt"

    # 1. 检查今日是否已运行 (通过 Git 记录判断仓库文件是否今天更新过)
    force_update = os.environ.get("FORCE_UPDATE", "false").lower() == "true"
    if not force_update and os.path.exists(output_file):
        try:
            import subprocess
            # 获取 deip.txt 最后一次提交的短日期 (YYYY-MM-DD)
            last_commit_date = subprocess.check_output(
                ['git', 'log', '-1', '--format=%ad', '--date=short', output_file],
                stderr=subprocess.DEVNULL
            ).decode('utf-8').strip()
            
            today_date = datetime.now().strftime("%Y-%m-%d")
            if last_commit_date == today_date:
                print(f"检测到仓库中 {output_file} 今日已更新 ({last_commit_date})，跳过执行。")
                return
        except Exception as e:
            # 如果没有 git 环境或获取失败，则保底不跳过
            print(f"无法获取 Git 记录，将继续执行：{e}")

    # 2. 从变量读取模板
    template_raw = os.environ.get("VMESS_TEMPLATE")
    if not template_raw:
        print("错误: 请在 GitHub Secrets 中设置 VMESS_TEMPLATE")
        return
    
    try:
        base_obj = decode_vmess(template_raw)
    except Exception as e:
        print(f"解析模板失败: {e}")
        return

    # 3. 获取 IP 列表 (优先从本地读取，无本地文件则从网络下载)
    lines = []
    ip_local_file = "cfyxip.txt"
    if os.path.exists(ip_local_file):
        print(f"检测到本地 IP 列表，正在读取: {ip_local_file}")
        with open(ip_local_file, "r") as f:
            lines = f.readlines()
    else:
        print(f"正在从网络获取 IP 列表: {ip_list_url}...")
        try:
            resp = requests.get(ip_list_url)
            resp.raise_for_status()
            lines = resp.text.splitlines()
        except Exception as e:
            print(f"获取 IP 失败: {e}")
            return

    region_map = {region: [] for region in target_regions}
    for line in lines:
        if "#" in line and ":" in line:
            parts = line.split("#")
            region = parts[1].strip()
            if region in region_map:
                addr_port = parts[0].strip().split(":")
                region_map[region].append({"add": addr_port[0], "port": addr_port[1]})

    # 4. 生成新节点
    generated_nodes = []
    for region in target_regions:
        ips = region_map[region][:per_region_count]
        for i, item in enumerate(ips):
            new_obj = base_obj.copy()
            new_obj["add"] = item["add"]
            new_obj["port"] = item["port"]
            # 命名规范: 地区 + 序号 (例如 AE01)
            new_obj["ps"] = f"{region}{i+1:02d}"
            generated_nodes.append(encode_vmess(new_obj))

    # 5. 写入 deip.txt
    if generated_nodes:
        with open(output_file, "w") as f:
            f.write("\n".join(generated_nodes))
        print(f"成功生成 {len(generated_nodes)} 个节点到 {output_file}")
