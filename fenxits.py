'''
Author: 
Date: 2025-01-21 13:25:54
LastEditors: Please set LastEditors
LastEditTime: 2025-01-21 13:27:18
Description: file content
'''
import re

def extract_avPlayer_info(ts_file_path):
    # 读取TypeScript文件内容
    with open(ts_file_path, 'r', encoding='utf-8') as file:
        content = file.read()

    # 正则表达式匹配 this.avPlayer 的方法调用
    method_pattern = re.compile(r'this\.avPlayer[?!]?\.(\w+)\(([^)]*)\)')
    methods = method_pattern.findall(content)

    # 正则表达式匹配 this.avPlayer 的属性访问
    property_pattern = re.compile(r'this\.avPlayer[?!]?\.(\w+)(?:\s*:\s*(\w+))?')
    properties = property_pattern.findall(content)

    # 打印方法调用信息
    print("Methods used on this.avPlayer:")
    for method_name, method_args in methods:
        print(f"- {method_name}({method_args})")

    # 打印属性访问信息
    print("\nProperties accessed on this.avPlayer:")
    for prop_name, prop_type in properties:
        if prop_type:
            print(f"- {prop_name}: {prop_type}")
        else:
            print(f"- {prop_name}")

# 使用示例
ts_file_path = r'D:\source\aloeplayer_ohos\video_player\video_player_ohos\ohos\src\main\ets\components\videoplayer\VideoPlayer.ets'  # 替换为你的TypeScript文件路径
extract_avPlayer_info(ts_file_path)
