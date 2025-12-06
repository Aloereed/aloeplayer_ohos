// Libsmb2Service 使用示例
//
// 此文件展示了如何使用 Libsmb2Service 来访问 SMB 共享文件

import 'dart:typed_data';
import 'package:aloeplayer/libsmb2_service/libsmb2_service_lib.dart';

void main() async {
  // 创建服务实例
  final smbService = Libsmb2Service();

  try {
    print('正在连接到 SMB 服务器...');

    // 连接到 SMB 共享
    // 注意: host 格式应为 //server/share 或 server/share
    final connected = await smbService.connect(
      host: '//192.168.1.100/Media',  // 修改为您的服务器地址
      username: 'your_username',       // 修改为您的用户名
      password: 'your_password',       // 修改为您的密码
      domain: 'WORKGROUP',             // 修改为您的域名
    );

    if (!connected) {
      print('连接失败');
      return;
    }

    print('✅ 连接成功!');
    print('');

    // 示例 1: 列出根目录的文件
    print('📁 列出根目录:');
    final rootFiles = await smbService.listFiles('/');
    for (final file in rootFiles) {
      final icon = file.isDirectory ? '📁' : '📄';
      final sizeStr = file.isDirectory ? '' : ' (${_formatSize(file.size)})';
      print('  $icon ${file.name}$sizeStr');
    }
    print('');

    // 示例 2: 列出子目录
    if (rootFiles.isNotEmpty && rootFiles.first.isDirectory) {
      final subDir = rootFiles.first.path;
      print('📁 列出子目录: $subDir');
      try {
        final subFiles = await smbService.listFiles(subDir);
        for (final file in subFiles) {
          final icon = file.isDirectory ? '📁' : '📄';
          print('  $icon ${file.name}');
        }
        print('');
      } catch (e) {
        print('  无法列出目录: $e');
        print('');
      }
    }

    // 示例 3: 获取文件信息
    final firstFile = rootFiles.firstWhere(
      (f) => !f.isDirectory,
      orElse: () => rootFiles.first,
    );

    if (!firstFile.isDirectory) {
      print('📄 文件信息: ${firstFile.name}');
      final fileInfo = await smbService.getFile(firstFile.path);
      print('  路径: ${fileInfo.path}');
      print('  大小: ${_formatSize(fileInfo.size)}');
      print('  修改时间: ${fileInfo.modifiedTime}');
      print('  创建时间: ${fileInfo.createdTime}');
      print('');

      // 示例 4: 读取文件流（只读取前 1KB 作为示例）
      print('📥 读取文件流: ${firstFile.name}');
      try {
        final stream = await smbService.getFileStream(firstFile.path);
        int totalBytes = 0;
        int maxBytes = 1024; // 只读取 1KB

        await for (final chunk in stream) {
          totalBytes += chunk.length;
          print('  读取了 ${chunk.length} 字节 (总计: $totalBytes)');

          if (totalBytes >= maxBytes) {
            print('  达到预设限制 ($maxBytes 字节)，停止读取');
            break;
          }
        }
        print('');
      } catch (e) {
        print('  读取文件失败: $e');
        print('');
      }
    }

    // 示例 5: 保存凭据
    print('💾 保存连接凭据...');
    await smbService.saveCredentials(
      host: '//192.168.1.100/Media',
      username: 'your_username',
      password: 'your_password',
      domain: 'WORKGROUP',
    );
    print('✅ 凭据已保存');
    print('');

    // 示例 6: 读取保存的凭据
    print('📖 读取保存的凭据...');
    final credentials = await smbService.getSavedCredentials();
    print('  主机: ${credentials['host']}');
    print('  用户名: ${credentials['username']}');
    print('  域: ${credentials['domain']}');
    print('');

  } catch (e, stackTrace) {
    print('❌ 错误: $e');
    print('堆栈跟踪:');
    print(stackTrace);
  } finally {
    // 清理资源
    print('断开连接...');
    await smbService.disconnect();
    print('👋 已断开');
  }
}

// 辅助函数: 格式化文件大小
String _formatSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  } else if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  } else if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  } else {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

// 高级示例: 递归列出所有文件
Future<void> listAllFilesRecursive(
  Libsmb2Service service,
  String path, {
  int depth = 0,
}) async {
  final indent = '  ' * depth;

  try {
    final files = await service.listFiles(path);

    for (final file in files) {
      final icon = file.isDirectory ? '📁' : '📄';
      print('$indent$icon ${file.name}');

      if (file.isDirectory) {
        // 递归列出子目录
        await listAllFilesRecursive(service, file.path, depth: depth + 1);
      }
    }
  } catch (e) {
    print('$indent❌ 无法访问: $e');
  }
}

// 高级示例: 下载整个文件到内存
Future<Uint8List?> downloadFile(
  Libsmb2Service service,
  String filePath,
) async {
  try {
    final fileInfo = await service.getFile(filePath);
    print('正在下载: ${fileInfo.name} (${_formatSize(fileInfo.size)})');

    final stream = await service.getFileStream(filePath);
    final chunks = <Uint8List>[];
    int totalBytes = 0;

    await for (final chunk in stream) {
      chunks.add(chunk);
      totalBytes += chunk.length;
      final progress = (totalBytes / fileInfo.size * 100).toStringAsFixed(1);
      print('  进度: $progress% ($totalBytes/${fileInfo.size})');
    }

    // 合并所有块
    final result = Uint8List(totalBytes);
    int offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    print('✅ 下载完成!');
    return result;
  } catch (e) {
    print('❌ 下载失败: $e');
    return null;
  }
}
