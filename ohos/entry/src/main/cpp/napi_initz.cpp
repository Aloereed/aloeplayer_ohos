#include "napi/native_api.h"
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
}
#include "hilog/log.h"

#include <future>
#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200 // 全局domain宏，标识业务领域
#define LOG_TAG "MY_TAG"  // 全局tag宏，标识模块日志tag


#include <iostream>
#include <fstream>
#include <vector>
#include <map>
#include <chrono>
#include <sstream>

#include <cstdio>
#include <cstring>

// 假设OH_LOG_ERROR宏已定义

void extract_subtitles(const char *filename) {
    AVFormatContext *fmt_ctx = nullptr;
    int ret = avformat_open_input(&fmt_ctx, filename, nullptr, nullptr);
    if (ret < 0) {
        char error_buf[AV_ERROR_MAX_STRING_SIZE] = {0};
        av_strerror(ret, error_buf, sizeof(error_buf));
        OH_LOG_ERROR(LOG_APP, "Could not open file '%{public}s': %{public}s", filename, error_buf);
        return;
    }

    if ((ret = avformat_find_stream_info(fmt_ctx, nullptr)) < 0) {
        char error_buf[AV_ERROR_MAX_STRING_SIZE] = {0};
        av_strerror(ret, error_buf, sizeof(error_buf));
        OH_LOG_ERROR(LOG_APP, "Could not find stream information: %{public}s", error_buf);
        avformat_close_input(&fmt_ctx);
        return;
    }

    for (unsigned i = 0; i < fmt_ctx->nb_streams; i++) {
        AVStream *stream = fmt_ctx->streams[i];
        if (stream->codecpar->codec_type != AVMEDIA_TYPE_SUBTITLE)
            continue;

        const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
        if (!codec) {
            OH_LOG_ERROR(LOG_APP, "Unsupported codec for subtitle stream %u", i);
            continue;
        }

        AVCodecContext *codec_ctx = avcodec_alloc_context3(codec);
        if (!codec_ctx) {
            OH_LOG_ERROR(LOG_APP, "Failed to allocate codec context for stream %u", i);
            continue;
        }

        if ((ret = avcodec_parameters_to_context(codec_ctx, stream->codecpar)) < 0) {
            char error_buf[AV_ERROR_MAX_STRING_SIZE] = {0};
            av_strerror(ret, error_buf, sizeof(error_buf));
            OH_LOG_ERROR(LOG_APP, "Failed to copy codec parameters: %{public}s", error_buf);
            avcodec_free_context(&codec_ctx);
            continue;
        }

        if ((ret = avcodec_open2(codec_ctx, codec, nullptr)) < 0) {
            char error_buf[AV_ERROR_MAX_STRING_SIZE] = {0};
            av_strerror(ret, error_buf, sizeof(error_buf));
            OH_LOG_ERROR(LOG_APP, "Failed to open codec: %{public}s", error_buf);
            avcodec_free_context(&codec_ctx);
            continue;
        }

        const char *ext = nullptr;
        if (codec_ctx->codec_id == AV_CODEC_ID_ASS || codec_ctx->codec_id == AV_CODEC_ID_SSA) {
            ext = "ass";
        } else if (codec_ctx->codec_id == AV_CODEC_ID_SUBRIP) {
            ext = "srt";
        } else {
            OH_LOG_ERROR(LOG_APP, "Unsupported subtitle format for stream %u", i);
            avcodec_free_context(&codec_ctx);
            continue;
        }

        char output_filename[256];
        std::string ifile(filename);

        snprintf(output_filename, sizeof(output_filename), "_%u.%s", i, ext);
        FILE *output_file = fopen((ifile + output_filename).c_str(), "wb");
        if (!output_file) {
            OH_LOG_ERROR(LOG_APP, "Could not open output file: %{public}s", output_filename);
            avcodec_free_context(&codec_ctx);
            continue;
        }

        // Write ASS header
        if (strcmp(ext, "ass") == 0 && codec_ctx->subtitle_header) {
            fwrite(codec_ctx->subtitle_header, 1, codec_ctx->subtitle_header_size, output_file);
            if (codec_ctx->subtitle_header[codec_ctx->subtitle_header_size - 1] != '\n') {
                fputc('\n', output_file);
            }
        }

        AVPacket *pkt = av_packet_alloc();
        if (!pkt) {
            OH_LOG_ERROR(LOG_APP, "Failed to allocate packet");
            fclose(output_file);
            avcodec_free_context(&codec_ctx);
            continue;
        }

        int srt_counter = 1;

        while (av_read_frame(fmt_ctx, pkt) >= 0) {
            if (pkt->stream_index != static_cast<int>(i)) {
                av_packet_unref(pkt);
                continue;
            }

            ret = avcodec_send_packet(codec_ctx, pkt);
            if (ret < 0) {
                av_packet_unref(pkt);
                continue;
            }

            while (ret >= 0) {
                AVSubtitle sub;
                memset(&sub, 0, sizeof(sub));
                int got_subtitle = 0;
                ret = avcodec_decode_subtitle2(codec_ctx, &sub, &got_subtitle, pkt);
                if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
                    break;
                if (ret < 0)
                    break;
                
                if (got_subtitle) {
                    for (unsigned j = 0; j < sub.num_rects; j++) {
                        AVSubtitleRect *rect = sub.rects[j];
                        if (!rect)
                            continue;

                        if (strcmp(ext, "ass") == 0 && rect->ass) {
                            fprintf(output_file, "%s\n", rect->ass);
                        } else if (strcmp(ext, "srt") == 0 && rect->text) {
                            double start = sub.pts * av_q2d(stream->time_base) + sub.start_display_time / 1000.0;
                            double end = sub.pts * av_q2d(stream->time_base) + sub.end_display_time / 1000.0;

                            fprintf(output_file, "%d\n%02d:%02d:%02d,%03d --> %02d:%02d:%02d,%03d\n%s\n\n",
                                    srt_counter++, static_cast<int>(start / 3600) % 24,
                                    static_cast<int>(start / 60) % 60, static_cast<int>(start) % 60,
                                    static_cast<int>((start - static_cast<int>(start)) * 1000),
                                    static_cast<int>(end / 3600) % 24, static_cast<int>(end / 60) % 60,
                                    static_cast<int>(end) % 60, static_cast<int>((end - static_cast<int>(end)) * 1000),
                                    rect->text);
                        }
                    }
                    avsubtitle_free(&sub);
                }
            }
            av_packet_unref(pkt);
        }

        av_packet_free(&pkt);
        fclose(output_file);
        avcodec_free_context(&codec_ctx);
    }

    avformat_close_input(&fmt_ctx);
}
#include <iostream>
#include <vector>
#include <string>
#include <sstream>
#include <cstring>

// 函数：将参数字符串转换为 argc 和 argv
void parseCommandLine(const std::string &input, int &argc, char **&argv) {
    // 用于存储分割后的参数
    std::vector<std::string> args;
    std::string currentArg;
    bool inQuotes = false; // 是否在引号内

    for (size_t i = 0; i < input.size(); ++i) {
        char c = input[i];

        if (c == '\"') {
            // 如果遇到引号，切换引号状态
            inQuotes = !inQuotes;
        } else if (c == ' ' && !inQuotes) {
            // 如果遇到空格且不在引号内，将当前参数保存
            if (!currentArg.empty()) {
                args.push_back(currentArg);
                currentArg.clear();
            }
        } else {
            // 将字符加入当前参数
            currentArg += c;
        }
    }

    // 保存最后一个参数（如果存在）
    if (!currentArg.empty()) {
        args.push_back(currentArg);
    }

    // 设置 argc
    argc = static_cast<int>(args.size());

    // 分配 argv
    argv = new char *[argc];
    for (int i = 0; i < argc; ++i) {
        argv[i] = new char[args[i].size() + 1];
        std::strcpy(argv[i], args[i].c_str());
    }
}


std::string global_result;
static napi_value Getsrt(napi_env env, napi_callback_info info) {
    // 输入参数个数
    OH_LOG_ERROR(LOG_APP, "cpp side start");


    size_t argc = 1;

    // 输入参数数组

    napi_value args[1] = {nullptr};

    // 将获取的传入参数放入数组中

    if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {

        return nullptr;
    }

    // 上面的你就能把输入的字符串放入args[0]中了，下面就是写对应的调用逻辑

    // 记录长度

    size_t typeLen = 0;

    // char类型的转换

    char *str = nullptr;

    // 写入缓存，获得args[0]对应的char长度

    napi_get_value_string_utf8(env, args[0], nullptr, 0, &typeLen);

    // napi_get_value_string_utf8（env，数组对象，char，缓存长度，获取的长度）主要作用是通过缓存复制的方法，将对象转换为char，复制到缓存中，获取长度

    str = new char[typeLen + 1];

    // 获取输入的字符串转换为char类型的str

    napi_get_value_string_utf8(env, args[0], str, typeLen + 1, &typeLen);

    // 然后你就可以写对应的加密之类的操作了，这个自己写，我跳过了
    //  示例输入
    std::string input(str, typeLen);

    int _argc;
    char **_argv;

    // 解析输入
    parseCommandLine(input, _argc, _argv);
    std::cout << "argc: " << _argc << std::endl;
    OH_LOG_ERROR(LOG_APP, "Argc:%{public}d, argv:%{public}s", _argc, str);
    // extract_subtitle(_argc, _argv);
    extract_subtitles(_argv[1]);
    // 输出 argc 和 argv

    //     std::thread thread_obj([&]() {
    //         main_function(_argc, _argv);
    //     });


    // 释放动态分配的内存
    //     for (int i = 0; i < argc; ++i) {
    //         delete[] argv[i];
    //     }
    //     delete[] argv;
    //
    //     main_function(, char **argv)

    // 创建输出对象

    napi_value output;

    // 将char类型的str，赋值给output,类型为string

    napi_create_string_utf8(env, global_result.c_str(), global_result.size(), &output);

    // 返回的是长度

    // napi_create_double(env, typeLen, &output);

    return output;

    //    return args[0];//这个是直接返回输入对象
}
static napi_value Add(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};

    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_valuetype valuetype0;
    napi_typeof(env, args[0], &valuetype0);

    napi_valuetype valuetype1;
    napi_typeof(env, args[1], &valuetype1);

    double value0;
    napi_get_value_double(env, args[0], &value0);

    double value1;
    napi_get_value_double(env, args[1], &value1);

    napi_value sum;
    napi_create_double(env, value0 + value1, &sum);

    return sum;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {{"add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr},
                                       {"getsrt", nullptr, Getsrt, nullptr, nullptr, nullptr, napi_default, nullptr}};
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) { napi_module_register(&demoModule); }
