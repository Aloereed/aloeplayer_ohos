# 重命名所有.so.版本号文件为.so文件
import os

def rename_file(file_path):
    file_list = os.listdir(file_path)
    for file in file_list:
        if file.endswith('.so') or file.endswith('.py'):
            continue
        else:
            old_name = os.path.join(file_path, file)
            new_name = os.path.join(file_path, file.split('.')[0]+".so")
            os.rename(old_name, new_name)

if __name__ == '__main__':
    file_path = './'
    rename_file(file_path)