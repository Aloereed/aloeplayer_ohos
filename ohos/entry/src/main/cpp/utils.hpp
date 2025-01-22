/*
 * @Author: 
 * @Date: 2025-01-21 21:16:33
 * @LastEditors: 
 * @LastEditTime: 2025-01-21 21:17:31
 * @Description: file content
 */
#ifndef UTILS_HPP
#define UTILS_HPP
#include <functional>
#include <string>
struct CallBackInfo {
    // 用于处理 FFmpeg 命令执行进度的回调函数
    std::function<void(int progress)> onFFmpegProgress;

    // 用于处理 FFmpeg 命令执行失败的回调函数
    std::function<void(int errorCode, const std::string& errorMessage)> onFFmpegFail;

    // 用于处理 FFmpeg 命令执行成功的回调函数
    std::function<void()> onFFmpegSuccess;
};
struct Callbacks {
    // 用于处理 FFmpeg 命令执行进度的回调函数
    void (*onFFmpegProgress)(int progress);

    // 用于处理 FFmpeg 命令执行失败的回调函数
    void (*onFFmpegFail)(int errorCode, const char* errorMessage);

    // 用于处理 FFmpeg 命令执行成功的回调函数
    void (*onFFmpegSuccess)();
};
#endif // UTILS_HPP