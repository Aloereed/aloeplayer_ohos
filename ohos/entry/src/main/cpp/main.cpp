/*
 * @Author:
 * @Date: 2025-01-21 20:39:36
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-01-22 12:37:06
 * @Description: file content
 */
#include "utils.hpp"
#include <aki/jsbind.h>
extern "C"{
    #include<libavutil/log.h>
    #include<libavutil/error.h>
}
#include <vector>
#include <string>
#include <cstring> // for strdup
#include "hilog/log.h" 
#include "napi_init.h"
struct CallBackInfo {
    // 用于处理 FFmpeg 命令执行进度的回调函数
    const aki::JSFunction* onFFmpegProgress;

    // 用于处理 FFmpeg 命令执行失败的回调函数
    const aki::JSFunction* onFFmpegFail;

    // 用于处理 FFmpeg 命令执行成功的回调函数
    const aki::JSFunction* onFFmpegSuccess;
};

char **vector_to_argv(const std::vector<std::string> &vec) {
    // 分配足够的内存来存储 char* 指针（包括最后一个 nullptr）
    char **argv = new char *[vec.size() + 1];

    // 将每个 std::string 转换为 C 风格的字符串并存储到 argv 中
    for (size_t i = 0; i < vec.size(); ++i) {
        argv[i] = strdup(vec[i].c_str()); // 使用 strdup 复制字符串
    }

    // 最后一个元素必须是 nullptr，表示数组的结束
    argv[vec.size()] = nullptr;

    return argv;
}

void log_call_back(void *ptr, int level, const char *fmt, va_list vl) {
    static int print_prefix = 1;
    static int count;
    static char prev[1024];
    char line[1024];
    static int is_atty;
    av_log_format_line(ptr, level, fmt, vl, line, sizeof(line), &print_prefix);
    strcpy(prev, line);
    OH_LOG_ERROR(LOG_APP, "========> %{public}s", line);
}

void showLog(bool show) {
    if (show) {
        av_log_set_callback(log_call_back);
    }
}

int executeFFmpegCommandAPP(std::string uuid, int cmdLen, std::vector<std::string> argv) {
    char **argv1 = vector_to_argv(argv);

    CallBackInfo onActionListener;
    // int ret = exe_ffmpeg_cmd(cmdLen, argv1, (int64_t) (&onActionListener), progressCallBack, -1);
    onActionListener.onFFmpegProgress = aki::JSBind::GetJSFunction(uuid + "_onFFmpegProgress");
    onActionListener.onFFmpegFail = aki::JSBind::GetJSFunction(uuid + "_onFFmpegFail");
    onActionListener.onFFmpegSuccess = aki::JSBind::GetJSFunction(uuid + "_onFFmpegSuccess");

    // Callbacks callbacks = {
    //     .onFFmpegProgress = onFFmpegProgress, .onFFmpegFail = onFFmpegFail, .onFFmpegSuccess = onFFmpegSuccess};

    int ret = exe_ffmpeg_cmd(cmdLen, argv1, nullptr);
    if (ret != 0) {
        char err[1024] = {0};
        int nRet = av_strerror(ret, err, 1024);
        onActionListener.onFFmpegFail->Invoke<void>(ret, err);
    } else {
        onActionListener.onFFmpegSuccess->Invoke<void>();
    }

    for (int i = 0; i < cmdLen; ++i) {
        free(argv1[i]);
    }
    return ret;
}
int executeFFmpegCommandAPP2(std::string uuid, int cmdLen, std::vector<std::string> argv) {
    char **argv1 = vector_to_argv(argv);

    // Callbacks callbacks = {
    //     .onFFmpegProgress = onFFmpegProgress, .onFFmpegFail = onFFmpegFail, .onFFmpegSuccess = onFFmpegSuccess};
    CallBackInfo onActionListener;

    onActionListener.onFFmpegProgress = aki::JSBind::GetJSFunction(uuid + "_onFFmpegProgress");
    onActionListener.onFFmpegFail = aki::JSBind::GetJSFunction(uuid + "_onFFmpegFail");
    onActionListener.onFFmpegSuccess = aki::JSBind::GetJSFunction(uuid + "_onFFmpegSuccess");
    int ret = extract_subtitle(cmdLen, argv1);
    if (ret != 0) {
        char err[1024] = {0};
        onActionListener.onFFmpegFail->Invoke<void>(ret, err);
    } else {
        onActionListener.onFFmpegSuccess->Invoke<void>();
    }

    for (int i = 0; i < cmdLen; ++i) {
        free(argv1[i]);
    }
    return ret;
}
JSBIND_ADDON(entry)

JSBIND_GLOBAL() {
    JSBIND_PFUNCTION(executeFFmpegCommandAPP);
    JSBIND_PFUNCTION(executeFFmpegCommandAPP2);
    JSBIND_FUNCTION(showLog);
}
