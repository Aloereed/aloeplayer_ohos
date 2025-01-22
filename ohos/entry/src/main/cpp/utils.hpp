#ifndef UTILS_H
#define UTILS_H

#ifdef __cplusplus
extern "C" {
#endif

// 定义回调函数类型
typedef void (*OnFFmpegProgress)(int progress);
typedef void (*OnFFmpegFail)(int errorCode, const char* errorMessage);
typedef void (*OnFFmpegSuccess)();

// 定义结构体并为其创建别名
typedef struct {
    OnFFmpegProgress onFFmpegProgress;      // 进度回调
    OnFFmpegFail onFFmpegFail;              // 失败回调
    OnFFmpegSuccess onFFmpegSuccess;        // 成功回调
} Callbacks;
int exe_ffmpeg_cmd(int argc, char **argv, Callbacks *callback) ;
#ifdef __cplusplus
}
#endif

#endif // UTILS_H
