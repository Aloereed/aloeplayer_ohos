// #include "napi/native_api.h"
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
#include <streambuf>
#include <chrono>
#include <sstream>
struct SubtitleInfo {
    int index;
    double start;
    double end;
    std::string text;
};
struct SubtitleStream {
    int index;                      // 流索引
    AVCodecContext *codec_ctx;      // 解码器上下文
    std::vector<SubtitleInfo> subs; // 字幕数据
    std::string output_filename;    // 输出文件名
};
// 用于缓存前一个字幕的信息
struct CachedSubtitle {
    int index;
    double start;
    double end;
    std::string text;
};

// 自定义 streambuf 类
#include <cstdio>

// class LogStreamBuf : public std::streambuf {
// protected:
//     virtual int overflow(int c) override {
//         if (c != EOF) {
//             buffer += static_cast<char>(c);
//             if (c == '\n') {
//                 // 使用 snprintf 生成格式化字符串
//                 char formatted_message[1024];
//                 snprintf(formatted_message, sizeof(formatted_message), "%s", buffer.c_str());
//                 OH_LOG_ERROR(LOG_APP, formatted_message);
//                 buffer.clear();
//             }
//         }
//         return c;
//     }

//     virtual int sync() override {
//         if (!buffer.empty()) {
//             char formatted_message[1024];
//             snprintf(formatted_message, sizeof(formatted_message), "%s", buffer.c_str());
//             OH_LOG_ERROR(LOG_APP, formatted_message);
//             buffer.clear();
//         }
//         return 0;
//     }

// private:
//     std::string buffer;
// };


// // 重定向 std::cout 和 std::cerr
// void redirectStdOutAndStdErr() {
//     static LogStreamBuf coutBuf("LOG_APP_COUT"); // 为 std::cout 创建自定义 streambuf
//     static LogStreamBuf cerrBuf("LOG_APP_CERR"); // 为 std::cerr 创建自定义 streambuf

//     // 重定向 std::cout
//     std::cout.rdbuf(&coutBuf);
//     // 重定向 std::cerr
//     std::cerr.rdbuf(&cerrBuf);
// }

// 生成带语言标识的文件名
std::string generate_filename(const AVStream *stream, const std::string &base) {
    std::stringstream ss;
    ss << base << "_";

    // 获取语言元数据
    AVDictionaryEntry *lang_tag = av_dict_get(stream->metadata, "language", nullptr, 0);
    if (lang_tag && lang_tag->value) {
        ss << lang_tag->value;
    } else {
        ss << "stream_" << stream->index;
    }
    ss << ".srt";
    return ss.str();
}


std::string format_time(double seconds) {
    int hr = static_cast<int>(seconds / 3600);
    int min = static_cast<int>((seconds - hr * 3600) / 60);
    int sec = static_cast<int>(seconds - hr * 3600 - min * 60);
    int ms = static_cast<int>((seconds - static_cast<int>(seconds)) * 1000);

    char buffer[256];
    snprintf(buffer, sizeof(buffer), "%02d:%02d:%02d,%03d", hr, min, sec, ms);
    return std::string(buffer);
}
// 辅助函数：自定义分割字符串，忽略转义逗号
std::vector<std::string> split_ignore_escaped(const std::string &str, char delimiter) {
    std::vector<std::string> tokens;
    std::string token;
    bool escaped = false; // 是否遇到转义字符

    for (char ch : str) {
        if (ch == '\\') {
            escaped = true; // 标记转义字符
            token += ch;
        } else if (ch == delimiter && !escaped) {
            // 遇到未转义的分隔符，分割字符串
            tokens.push_back(token);
            token.clear();
        } else {
            // 普通字符或转义后的分隔符
            token += ch;
            escaped = false; // 重置转义标志
        }
    }

    // 添加最后一个token
    if (!token.empty()) {
        tokens.push_back(token);
    }

    return tokens;
}

// 辅助函数：合并相邻字幕
void merge_adjacent_subtitles(std::vector<SubtitleInfo> &subs) {
    for (size_t i = 0; i + 1 < subs.size(); ) {
        if (subs[i].start == subs[i + 1].start) {
            // 合并文本
            subs[i].text += "\n" + subs[i + 1].text;
            // 更新结束时间为两者中较晚的那个
            subs[i].end = std::max(subs[i].end, subs[i + 1].end);
            // 删除后一个字幕
            subs.erase(subs.begin() + i + 1);
        } else {
            i++;
        }
    }
}

int extract_subtitle(int argc, char *argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <input_video>" << " <output_prefix>"<< std::endl;
        return 1;
    }
    // redirectStdOutAndStdErr();
    const char *filename = argv[1];
    const char *outputfilename = argv[2];
    AVFormatContext *fmt_ctx = nullptr;

    avformat_network_init();
    if (avformat_open_input(&fmt_ctx, filename, nullptr, nullptr) < 0) {
        std::cerr << "Could not open input file" << std::endl;
        return 1;
    }

    if (avformat_find_stream_info(fmt_ctx, nullptr) < 0) {
        std::cerr << "Failed to retrieve stream info" << std::endl;
        avformat_close_input(&fmt_ctx);
        return 1;
    }

    // 查找所有字幕流
    std::map<int, SubtitleStream> subtitle_streams;

    for (unsigned int i = 0; i < fmt_ctx->nb_streams; i++) {
        AVStream *stream = fmt_ctx->streams[i];
        AVCodecParameters *codecpar = stream->codecpar;

        if (codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
            const AVCodec *codec = avcodec_find_decoder(codecpar->codec_id);
            if (!codec) {
                std::cerr << "Unsupported subtitle codec for stream " << i << std::endl;
                continue;
            }

            // 初始化解码器上下文
            AVCodecContext *codec_ctx = avcodec_alloc_context3(codec);
            avcodec_parameters_to_context(codec_ctx, codecpar);

            if (avcodec_open2(codec_ctx, codec, nullptr) < 0) {
                std::cerr << "Failed to open codec for stream " << i << std::endl;
                avcodec_free_context(&codec_ctx);
                continue;
            }

            // 创建流信息结构
            SubtitleStream ss;
            ss.index = i;
            ss.codec_ctx = codec_ctx;
            ss.output_filename = generate_filename(stream, std::string(outputfilename) + "_");
            subtitle_streams[i] = ss;
        }
    }

    if (subtitle_streams.empty()) {
        std::cerr << "No subtitle streams found" << std::endl;
        avformat_close_input(&fmt_ctx);
        return 1;
    }

    AVPacket *pkt = av_packet_alloc();


    std::unordered_map<int, CachedSubtitle> cached_subtitles; // 按 stream_index 缓存前一个字幕

    // 处理所有数据包
    while (av_read_frame(fmt_ctx, pkt) >= 0) {
        auto it = subtitle_streams.find(pkt->stream_index);
        if (it != subtitle_streams.end()) {
            SubtitleStream &ss = it->second;
            AVSubtitle sub;
            int got_subtitle = 0;

            int ret = avcodec_decode_subtitle2(ss.codec_ctx, &sub, &got_subtitle, pkt);
            if (ret < 0) {
                std::cerr << "Error decoding subtitle in stream " << ss.index << std::endl;
                continue;
            }

            if (got_subtitle) {
                // 获取时间基转换参数
                AVStream *stream = fmt_ctx->streams[ss.index];
                double time_base = av_q2d(stream->time_base);

                double pts_seconds = pkt->pts * time_base;
                double start = pts_seconds + sub.start_display_time / 1000.0;
                double end = pts_seconds + sub.end_display_time / 1000.0;

                // 检查是否有缓存的前一个字幕
                if (cached_subtitles.find(ss.index) != cached_subtitles.end()) {
                    CachedSubtitle &cached_sub = cached_subtitles[ss.index];

                    // 如果前一个字幕的 end_display_time 等于 start_display_time
                    if (cached_sub.end == cached_sub.start) {
                        // 将当前字幕的 start_display_time - 100ms 作为前一个字幕的 end_display_time
                        cached_sub.end = start - 0.1; // 100ms = 0.1s
                        if (cached_sub.end < cached_sub.start) {
                            cached_sub.end = cached_sub.start; // 确保 end 不小于 start
                        }

                        // 确保前一个字幕的持续时间不超过 10 秒
                        if (cached_sub.end - cached_sub.start > 10.0) {
                            cached_sub.end = cached_sub.start + 10.0;
                        }

                        // 将前一个字幕添加到字幕列表中
                        ss.subs.push_back({cached_sub.index, cached_sub.start, cached_sub.end, cached_sub.text});
                    }

                    // 清除缓存
                    cached_subtitles.erase(ss.index);
                }

                std::string text;
                // 提取字幕文本
                for (unsigned i = 0; i < sub.num_rects; i++) {
                    if (!sub.rects[i])
                        continue;

                    AVSubtitleRect *rect = sub.rects[i];
                    const char *content = nullptr;
                    size_t length = 0;

                    if (rect->type == SUBTITLE_TEXT && rect->text) {
                        content = rect->text;
                        length = strlen(rect->text); // 安全获取长度
                    } else if (rect->type == SUBTITLE_ASS && rect->ass) {
                        content = rect->ass;
                        length = strlen(rect->ass);
                    }

                    if (content && length > 0) {
                        // 安全构造字符串
                        text.append(content, length);
                    }
                }

                // 如果当前字幕的 start_display_time 和 end_display_time 相等，缓存当前字幕
                if (sub.start_display_time == sub.end_display_time) {
                    cached_subtitles[ss.index] = {static_cast<int>(ss.subs.size() + 1), start, end, text};
                } else {
                    // 确保当前字幕的持续时间不超过 10 秒
                    if (end - start > 10.0) {
                        end = start + 10.0;
                    }

                    // 将当前字幕添加到字幕列表中
                    if (!text.empty()) {
                        ss.subs.push_back({static_cast<int>(ss.subs.size() + 1), start, end, text});
                    }
                }

                avsubtitle_free(&sub);
            }
        }
        av_packet_unref(pkt);
    }

    // 处理最后一个缓存字幕（如果有）
    for (auto &[stream_index, cached_sub] : cached_subtitles) {
        SubtitleStream &ss = subtitle_streams[stream_index];

        // 如果最后一个字幕的 end_display_time 等于 start_display_time
        if (cached_sub.end == cached_sub.start) {
            // 因为没有下一个字幕，直接设置持续时间为 10 秒
            cached_sub.end = cached_sub.start + 10.0;
        }

        // 将最后一个字幕添加到字幕列表中
        ss.subs.push_back({cached_sub.index, cached_sub.start, cached_sub.end, cached_sub.text});
    }


// 写入所有SRT文件
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <sstream>
#include <algorithm>


    // 写入所有SRT文件
    // void write_srt_files(const std::map<int, SubtitleStream> &subtitle_streams) {
    for (const auto &pair : subtitle_streams) {
        const SubtitleStream &ss = pair.second;
        std::ofstream srt_file(ss.output_filename);

        if (!srt_file.is_open()) {
            std::cerr << "Failed to create " << ss.output_filename << std::endl;
            continue;
        }

        // 复制字幕列表以便修改
        std::vector<SubtitleInfo> subs = ss.subs;

        // 处理文本中的逗号
        for (auto &sub : subs) {
            std::vector<std::string> tokens = split_ignore_escaped(sub.text, ',');
            if (tokens.size() >= 8) {
                // 只取最后一项作为文本
                sub.text = tokens.back();
                // 处理转义逗号
                size_t pos = 0;
                while ((pos = sub.text.find("\\,", pos)) != std::string::npos) {
                    sub.text.replace(pos, 2, ",");
                    pos += 1;
                }
            }
        }

        // 合并相邻字幕
        merge_adjacent_subtitles(subs);

        // 写入SRT文件
        for (const auto &sub : subs) {
            srt_file << sub.index << "\n"
                     << format_time(sub.start) << " --> " << format_time(sub.end) << "\n"
                     << sub.text << "\n\n";
        }

        std::cout << "Created: " << ss.output_filename << " (" << subs.size() << " subtitles)\n";
    }
    // }


    // 清理资源
    av_packet_free(&pkt);
    for (auto &pair : subtitle_streams) {
        avcodec_free_context(&pair.second.codec_ctx);
    }
    avformat_close_input(&fmt_ctx);

    return 0;
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


// std::string global_result;
// static napi_value Getsrt(napi_env env, napi_callback_info info) {
//     // 输入参数个数
//     OH_LOG_ERROR(LOG_APP, "cpp side start");


//     size_t argc = 1;

//     // 输入参数数组

//     napi_value args[1] = {nullptr};

//     // 将获取的传入参数放入数组中

//     if (napi_ok != napi_get_cb_info(env, info, &argc, args, nullptr, nullptr)) {

//         return nullptr;
//     }

//     // 上面的你就能把输入的字符串放入args[0]中了，下面就是写对应的调用逻辑

//     // 记录长度

//     size_t typeLen = 0;

//     // char类型的转换

//     char *str = nullptr;

//     // 写入缓存，获得args[0]对应的char长度

//     napi_get_value_string_utf8(env, args[0], nullptr, 0, &typeLen);

//     // napi_get_value_string_utf8（env，数组对象，char，缓存长度，获取的长度）主要作用是通过缓存复制的方法，将对象转换为char，复制到缓存中，获取长度

//     str = new char[typeLen + 1];

//     // 获取输入的字符串转换为char类型的str

//     napi_get_value_string_utf8(env, args[0], str, typeLen + 1, &typeLen);

//     // 然后你就可以写对应的加密之类的操作了，这个自己写，我跳过了
//     //  示例输入
//     std::string input(str, typeLen);

//     int _argc;
//     char **_argv;

//     // 解析输入
//     parseCommandLine(input, _argc, _argv);
//     std::cout << "argc: " << _argc << std::endl;
//     OH_LOG_ERROR(LOG_APP, "Argc:%{public}d, argv:%{public}s", _argc, str);
//     extract_subtitle(_argc, _argv);
//     // 输出 argc 和 argv

//     //     std::thread thread_obj([&]() {
//     //         main_function(_argc, _argv);
//     //     });


//     // 释放动态分配的内存
//     //     for (int i = 0; i < argc; ++i) {
//     //         delete[] argv[i];
//     //     }
//     //     delete[] argv;
//     //
//     //     main_function(, char **argv)

//     // 创建输出对象

//     napi_value output;

//     // 将char类型的str，赋值给output,类型为string

//     napi_create_string_utf8(env, global_result.c_str(), global_result.size(), &output);

//     // 返回的是长度

//     // napi_create_double(env, typeLen, &output);

//     return output;

//     //    return args[0];//这个是直接返回输入对象
// }
// static napi_value Add(napi_env env, napi_callback_info info) {
//     size_t argc = 2;
//     napi_value args[2] = {nullptr};

//     napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

//     napi_valuetype valuetype0;
//     napi_typeof(env, args[0], &valuetype0);

//     napi_valuetype valuetype1;
//     napi_typeof(env, args[1], &valuetype1);

//     double value0;
//     napi_get_value_double(env, args[0], &value0);

//     double value1;
//     napi_get_value_double(env, args[1], &value1);

//     napi_value sum;
//     napi_create_double(env, value0 + value1, &sum);

//     return sum;
// }

// EXTERN_C_START
// static napi_value Init(napi_env env, napi_value exports) {
//     napi_property_descriptor desc[] = {{"add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr},
//                                        {"getsrt", nullptr, Getsrt, nullptr, nullptr, nullptr, napi_default, nullptr}};
//     napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
//     return exports;
// }
// EXTERN_C_END

// static napi_module demoModule = {
//     .nm_version = 1,
//     .nm_flags = 0,
//     .nm_filename = nullptr,
//     .nm_register_func = Init,
//     .nm_modname = "entry",
//     .nm_priv = ((void *)0),
//     .reserved = {0},
// };

// extern "C" __attribute__((constructor)) void RegisterEntryModule(void) { napi_module_register(&demoModule); }
