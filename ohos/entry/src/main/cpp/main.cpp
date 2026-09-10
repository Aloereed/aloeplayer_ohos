/*
 * @Author:
 * @Date: 2025-01-21 20:39:36
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-04-02 18:18:21
 * @Description: file content
 */
#include "utils.hpp"
#include "library_media_probe.h"
#include <aki/jsbind.h>
extern "C" {
#include <libavutil/log.h>
#include <libavutil/error.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h> 
#include <libavutil/hdr_dynamic_metadata.h>
#include <libavutil/mastering_display_metadata.h>
#include <ass/ass.h>
}
#include <vector>
#include <string>
#include <cstring> // for strdup
#include "hilog/log.h"
#include "napi_init.h"
// #include "napi_new.h"
#include <taglib/tag.h>
#include <taglib/fileref.h>
#include <taglib/id3v2tag.h>
#include <taglib/mpegfile.h>
#include <taglib/flacfile.h>
#include <taglib/oggfile.h>
#include <taglib/vorbisfile.h>
#include <taglib/mp4file.h>
#include <taglib/attachedpictureframe.h>
#include <taglib/unsynchronizedlyricsframe.h>
#include <taglib/textidentificationframe.h>
#include <csignal>
#include <csetjmp>
#include <locale>
#include <codecvt>
#include <chrono>

#include <iostream>
#include <cstdio>
#include <cstdlib>
#include <cstdarg>

#include <png.h>
std::string toUTF8(const std::wstring &wstr) {
    std::wstring_convert<std::codecvt_utf8<wchar_t>> converter;
    return converter.to_bytes(wstr);
}

// Bound library probes, including providers that stop responding during I/O.
static int interrupt_library_probe(void* opaque) {
    const auto* deadline = static_cast<const std::chrono::steady_clock::time_point*>(opaque);
    return std::chrono::steady_clock::now() >= *deadline;
}

int64_t get_video_duration(const std::string &file_path) {
    // 初始化libavformat，并注册所有的muxers/demuxers
    // av_register_all();

    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    AVFormatContext *format_ctx = avformat_alloc_context();
    if (!format_ctx) return -1;
    format_ctx->interrupt_callback = {interrupt_library_probe, &deadline};

    // 打开视频文件
    if (avformat_open_input(&format_ctx, file_path.c_str(), nullptr, nullptr) != 0) {
        std::cerr << "无法打开视频文件: " << file_path << std::endl;
        return -1;
    }

    // 获取流信息
    if (avformat_find_stream_info(format_ctx, nullptr) < 0) {
        std::cerr << "无法获取流信息" << std::endl;
        avformat_close_input(&format_ctx);
        return -1;
    }

    // 获取视频时长（以微秒为单位）
    int64_t duration = format_ctx->duration;

    // 关闭视频文件
    avformat_close_input(&format_ctx);

    // 将微秒转换为毫秒
    return duration == AV_NOPTS_VALUE || duration < 0 ? 0 : duration / 1000;
}

// 结构体定义用于返回音轨和字幕轨信息
struct TrackInfo {
    int index;
    std::string language;
    // 可以根据需要添加更多字段
};

// 帮助函数：检查视频是否为HDR
bool isHDRVideo(const char* filePath) {
    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    AVFormatContext* formatContext = avformat_alloc_context();
    if (!formatContext) return false;
    formatContext->interrupt_callback = {interrupt_library_probe, &deadline};
    bool isHDR = false;

    // 初始化FFmpeg库（在较新版本的FFmpeg中不需要）
    #if LIBAVFORMAT_VERSION_INT < AV_VERSION_INT(58, 9, 100)
        av_register_all();
    #endif

    // 打开输入文件
    if (avformat_open_input(&formatContext, filePath, nullptr, nullptr) != 0) {
        std::cerr << "Cannot open input file: " << filePath << std::endl;
        return false;
    }

    // 读取流信息
    if (avformat_find_stream_info(formatContext, nullptr) < 0) {
        std::cerr << "Cannot find stream information" << std::endl;
        avformat_close_input(&formatContext);
        return false;
    }

    // 遍历所有流，寻找视频流
    for (unsigned int i = 0; i < formatContext->nb_streams; i++) {
        AVStream* stream = formatContext->streams[i];
        if (stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            // 检查是否含有HDR相关的side data
            for (int j = 0; j < stream->nb_side_data; j++) {
                const AVPacketSideData* sd = &stream->side_data[j];
                if (sd->type == AV_PKT_DATA_MASTERING_DISPLAY_METADATA ||
                    sd->type == AV_PKT_DATA_CONTENT_LIGHT_LEVEL) {
                    isHDR = true;
                    break;
                }
            }
            
            // 检查帧中是否有HDR元数据 - 使用简化的方法
            if (!isHDR) {
                // 获取解码器
                const AVCodec* codec = avcodec_find_decoder(stream->codecpar->codec_id);
                if (codec) {
                    AVCodecContext* codecContext = avcodec_alloc_context3(codec);
                    if (codecContext) {
                        if (avcodec_parameters_to_context(codecContext, stream->codecpar) >= 0) {
                            if (avcodec_open2(codecContext, codec, NULL) >= 0) {
                                // 检查色彩空间信息
                                if (codecContext->color_primaries == AVCOL_PRI_BT2020 &&
                                    (codecContext->color_trc == AVCOL_TRC_SMPTE2084 || 
                                     codecContext->color_trc == AVCOL_TRC_ARIB_STD_B67)) {
                                    isHDR = true;
                                }
                            }
                        }
                        avcodec_free_context(&codecContext);
                    }
                }
            }
            
            // 检查色彩空间特征
            if (!isHDR && stream->codecpar->color_primaries == AVCOL_PRI_BT2020 &&
                (stream->codecpar->color_trc == AVCOL_TRC_SMPTE2084 || 
                 stream->codecpar->color_trc == AVCOL_TRC_ARIB_STD_B67)) {
                isHDR = true;
            }
            
            break;  // 只检查第一个视频流
        }
    }

    avformat_close_input(&formatContext);
    return isHDR;
}

// 实现导出函数1：获取视频是否为HDR
std::string GetVideoHDRInfo(const std::string& filePath) {
    bool isHDR = false;
    try{
        isHDR = isHDRVideo(filePath.c_str());
    }catch(...){
        std::cerr << "Cannot find stream information" << std::endl;
        return "{\"isHDR\": false}"; 
    }
    
    // 构造JSON返回结果
    std::ostringstream json;
    json << "{\"isHDR\": " << (isHDR ? "true" : "false") << "}";
    
    return json.str();
}

// 实现导出函数2：获取所有音轨及其语言
std::string GetAudioTracks(const std::string& filePath) {
    AVFormatContext* formatContext = nullptr;
    std::ostringstream json;
    json << "{\"audioTracks\": [";

    // 初始化FFmpeg库（在较新版本的FFmpeg中不需要）
    #if LIBAVFORMAT_VERSION_INT < AV_VERSION_INT(58, 9, 100)
        av_register_all();
    #endif

    // 打开输入文件
    if (avformat_open_input(&formatContext, filePath.c_str(), nullptr, nullptr) != 0) {
        json << "]}";
        return json.str();
    }

    // 读取流信息
    if (avformat_find_stream_info(formatContext, nullptr) < 0) {
        avformat_close_input(&formatContext);
        json << "]}";
        return json.str();
    }

    bool firstTrack = true;
    // 遍历所有流，寻找音频流
    for (unsigned int i = 0; i < formatContext->nb_streams; i++) {
        AVStream* stream = formatContext->streams[i];
        if (stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            if (!firstTrack) {
                json << ",";
            }
            firstTrack = false;
            
            json << "{\"index\": " << i;
            
            // 尝试获取语言标签
            AVDictionaryEntry* lang = av_dict_get(stream->metadata, "language", nullptr, 0);
            if (lang) {
                json << ", \"language\": \"" << lang->value << "\"";
            } else {
                json << ", \"language\": \"und\"";
            }
            
            // 获取编解码器名称
            const AVCodec* codec = avcodec_find_decoder(stream->codecpar->codec_id);
            if (codec) {
                json << ", \"codec\": \"" << codec->name << "\"";
            }
            
            // 获取通道数
            if (stream->codecpar->ch_layout.nb_channels > 0) {
                json << ", \"channels\": " << stream->codecpar->ch_layout.nb_channels;
            } else {
                // 对于较旧版本的FFmpeg，可能需要使用不同的方式获取通道数
                json << ", \"channels\": " << 0; // 使用默认值
            }
            
            // 获取采样率
            json << ", \"sampleRate\": " << stream->codecpar->sample_rate;
            
            json << "}";
        }
    }

    json << "]}";
    avformat_close_input(&formatContext);
    return json.str();
}

// 实现导出函数3：获取所有字幕轨及其语言
std::string GetSubtitleTracks(const std::string& filePath) {
    AVFormatContext* formatContext = nullptr;
    std::ostringstream json;
    json << "{\"subtitleTracks\": [";

    // 初始化FFmpeg库（在较新版本的FFmpeg中不需要）
    #if LIBAVFORMAT_VERSION_INT < AV_VERSION_INT(58, 9, 100)
        av_register_all();
    #endif

    // 打开输入文件
    if (avformat_open_input(&formatContext, filePath.c_str(), nullptr, nullptr) != 0) {
        json << "]}";
        return json.str();
    }

    // 读取流信息
    if (avformat_find_stream_info(formatContext, nullptr) < 0) {
        avformat_close_input(&formatContext);
        json << "]}";
        return json.str();
    }

    bool firstTrack = true;
    // 遍历所有流，寻找字幕流
    for (unsigned int i = 0; i < formatContext->nb_streams; i++) {
        AVStream* stream = formatContext->streams[i];
        if (stream->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
            if (!firstTrack) {
                json << ",";
            }
            firstTrack = false;
            
            json << "{\"index\": " << i;
            
            // 尝试获取语言标签
            AVDictionaryEntry* lang = av_dict_get(stream->metadata, "language", nullptr, 0);
            if (lang) {
                json << ", \"language\": \"" << lang->value << "\"";
            } else {
                json << ", \"language\": \"und\"";
            }
            
            // 获取字幕编解码器信息
            const AVCodec* codec = avcodec_find_decoder(stream->codecpar->codec_id);
            if (codec) {
                json << ", \"codec\": \"" << codec->name << "\"";
            }
            
            // 尝试获取字幕标题
            AVDictionaryEntry* title = av_dict_get(stream->metadata, "title", nullptr, 0);
            if (title) {
                json << ", \"title\": \"" << title->value << "\"";
            }
            
            json << "}";
        }
    }

    json << "]}";
    avformat_close_input(&formatContext);
    return json.str();
}

std::wstring fromUTF8(const std::string &str) {
    std::wstring_convert<std::codecvt_utf8<wchar_t>> converter;
    return converter.from_bytes(str);
}
struct CallBackInfo {
    // 用于处理 FFmpeg 命令执行进度的回调函数
    const aki::JSFunction *onFFmpegProgress;

    // 用于处理 FFmpeg 命令执行失败的回调函数
    const aki::JSFunction *onFFmpegFail;

    // 用于处理 FFmpeg 命令执行成功的回调函数
    const aki::JSFunction *onFFmpegSuccess;
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
    // int ret = extractAss(cmdLen, argv1);
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


#include "audio_tags.h"

// typedef struct image_s {
//     int width, height, stride;
//     unsigned char *buffer;      // RGBA32
// } image_t;

// ASS_Library *ass_library;
// ASS_Renderer *ass_renderer;
// ASS_Track *track;

// const std::string base64_chars =
//              "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
//              "abcdefghijklmnopqrstuvwxyz"
//              "0123456789+/";

// std::string base64_encode(const std::vector<unsigned char>& data) {
//     std::string encoded;
//     int i = 0;
//     unsigned char char_array_3[3];
//     unsigned char char_array_4[4];

//     for (const auto& byte : data) {
//         char_array_3[i++] = byte;
//         if (i == 3) {
//             char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
//             char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
//             char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
//             char_array_4[3] = char_array_3[2] & 0x3f;

//             for (i = 0; i < 4; i++) {
//                 encoded += base64_chars[char_array_4[i]];
//             }
//             i = 0;
//         }
//     }

//     if (i > 0) {
//         for (int j = i; j < 3; j++) {
//             char_array_3[j] = '\0';
//         }

//         char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
//         char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
//         char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
//         char_array_4[3] = char_array_3[2] & 0x3f;

//         for (int j = 0; j < i + 1; j++) {
//             encoded += base64_chars[char_array_4[j]];
//         }

//         while (i++ < 3) {
//             encoded += '=';
//         }
//     }

//     return encoded;
// }

// void msg_callback(int level, const char *fmt, va_list va, void *data)
// {
//     if (level > 6)
//         return;
//     std::cout << "libass: ";
//     std::vfprintf(stdout, fmt, va);
//     std::cout << std::endl;
// }

// static image_t *gen_image(int width, int height)
// {
//     image_t *img = new image_t;
//     img->width = width;
//     img->height = height;
//     img->stride = width * 4;
//     img->buffer = new unsigned char[height * width * 4]();
//     return img;
// }

// static void blend_single(image_t * frame, ASS_Image *img)
// {
//     unsigned char r = img->color >> 24;
//     unsigned char g = (img->color >> 16) & 0xFF;
//     unsigned char b = (img->color >> 8) & 0xFF;
//     unsigned char a = 255 - (img->color & 0xFF);

//     unsigned char *src = img->bitmap;
//     unsigned char *dst = frame->buffer + img->dst_y * frame->stride + img->dst_x * 4;

//     for (int y = 0; y < img->h; ++y) {
//         for (int x = 0; x < img->w; ++x) {
//             unsigned k = ((unsigned) src[x]) * a;
//             // For high-quality output consider using dithering instead;
//             // this static offset results in biased rounding but is faster
//             unsigned rounding_offset = 255 * 255 / 2;
//             // If the original frame is not in premultiplied alpha, convert it beforehand or adjust
//             // the blending code. For fully-opaque output frames there's no difference either way.
//             dst[x * 4 + 0] = (k *   r + (255 * 255 - k) * dst[x * 4 + 0] + rounding_offset) / (255 * 255);
//             dst[x * 4 + 1] = (k *   g + (255 * 255 - k) * dst[x * 4 + 1] + rounding_offset) / (255 * 255);
//             dst[x * 4 + 2] = (k *   b + (255 * 255 - k) * dst[x * 4 + 2] + rounding_offset) / (255 * 255);
//             dst[x * 4 + 3] = (k * 255 + (255 * 255 - k) * dst[x * 4 + 3] + rounding_offset) / (255 * 255);
//         }
//         src += img->stride;
//         dst += frame->stride;
//     }
// }

// static void blend(image_t * frame, ASS_Image *img)
// {
//     int cnt = 0;
//     while (img) {
//         blend_single(frame, img);
//         ++cnt;
//         img = img->next;
//     }
//     OH_LOG_ERROR(LOG_APP, "%{public}d images blended", cnt);

//     // Convert from pre-multiplied to straight alpha
//     // (not needed for fully-opaque output)
//     for (int y = 0; y < frame->height; y++) {
//         unsigned char *row = frame->buffer + y * frame->stride;
//         for (int x = 0; x < frame->width; x++) {
//             const unsigned char alpha = row[4 * x + 3];
//             if (alpha) {
//                 // For each color channel c:
//                 //   c = c / (255.0 / alpha)
//                 // but only using integers and a biased rounding offset
//                 const uint32_t offs = (uint32_t) 1 << 15;
//                 uint32_t inv = ((uint32_t) 255 << 16) / alpha + 1;
//                 row[x * 4 + 0] = (row[x * 4 + 0] * inv + offs) >> 16;
//                 row[x * 4 + 1] = (row[x * 4 + 1] * inv + offs) >> 16;
//                 row[x * 4 + 2] = (row[x * 4 + 2] * inv + offs) >> 16;
//             }
//         }
//     }
// }

// static std::string write_png_to_string(image_t *img)
// {
//     std::vector<unsigned char> buffer;
//     png_structp png_ptr = NULL;
//     png_infop info_ptr = NULL;
//     png_byte **volatile row_pointers = NULL;

//     // Create a custom write function to write to the buffer
//     auto write_data = [](png_structp png_ptr, png_bytep data, png_size_t length) {
//         std::vector<unsigned char> *buffer = static_cast<std::vector<unsigned char>*>(png_get_io_ptr(png_ptr));
//         buffer->insert(buffer->end(), data, data + length);
//     };

//     png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
//     if (!png_ptr) {
//         OH_LOG_ERROR(LOG_APP, "PNG Error creating write struct!" );
//         return "";
//     }

//     info_ptr = png_create_info_struct(png_ptr);
//     if (!info_ptr) {
//         OH_LOG_ERROR(LOG_APP,  "PNG Error creating info struct!");
//         png_destroy_write_struct(&png_ptr, NULL);
//         return "";
//     }

//     row_pointers = new png_byte*[img->height];
//     for (int k = 0; k < img->height; k++)
//         row_pointers[k] = img->buffer + img->stride * k;

//     if (setjmp(png_jmpbuf(png_ptr))) {
//         OH_LOG_ERROR(LOG_APP,  "PNG unknown error!" );
//         delete[] row_pointers;
//         png_destroy_write_struct(&png_ptr, &info_ptr);
//         return "";
//     }

//     png_set_write_fn(png_ptr, &buffer, write_data, NULL);
//     png_set_compression_level(png_ptr, 9);

//     png_set_IHDR(png_ptr, info_ptr, img->width, img->height,
//                  8, PNG_COLOR_TYPE_RGBA, PNG_INTERLACE_NONE,
//                  PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);

//     png_write_info(png_ptr, info_ptr);

//     png_write_image(png_ptr, row_pointers);
//     png_write_end(png_ptr, info_ptr);

//     delete[] row_pointers;
//     png_destroy_write_struct(&png_ptr, &info_ptr);

//     return base64_encode(buffer);
// }

// 初始化 libass 的函数
extern "C" {
#include "asstest.h"
}
bool init_libass(const std::string &assFilePath, int frame_w = 1280, int frame_h = 720) {
    int result = initassinner(assFilePath.c_str(), frame_w, frame_h);
    return result == 1 ? true : false;
}

// 获取指定时间的 PNG 数据的函数
std::string get_png_data_at_time(int milliseconds, int frame_w = 1280, int frame_h = 720) {
    std::string pngData = getPng(milliseconds, frame_w, frame_h);

    return pngData;
}

// 释放资源的函数
void cleanup_libass() { cleanupinner(); }


JSBIND_ADDON(entry)

JSBIND_GLOBAL() {
    JSBIND_PFUNCTION(executeFFmpegCommandAPP);
    JSBIND_PFUNCTION(executeFFmpegCommandAPP2);
    JSBIND_FUNCTION(showLog);
    JSBIND_FUNCTION(get_video_duration);
    JSBIND_FUNCTION(probeDurationFd);
    JSBIND_FUNCTION(probeHdrFd);
    JSBIND_FUNCTION(thumbnailFromFd);
    JSBIND_FUNCTION(GetVideoHDRInfo);
    JSBIND_FUNCTION(GetAudioTracks);
    JSBIND_FUNCTION(GetSubtitleTracks);
    JSBIND_PFUNCTION(getTitle);
    JSBIND_PFUNCTION(setTitle);
    JSBIND_PFUNCTION(getArtist);
    JSBIND_PFUNCTION(setArtist);
    JSBIND_PFUNCTION(getAlbum);
    JSBIND_PFUNCTION(setAlbum);
    JSBIND_PFUNCTION(getYear);
    JSBIND_PFUNCTION(setYear);
    JSBIND_PFUNCTION(getTrack);
    JSBIND_PFUNCTION(setTrack);
    JSBIND_PFUNCTION(getDisc);
    JSBIND_PFUNCTION(setDisc);
    JSBIND_PFUNCTION(getGenre);
    JSBIND_PFUNCTION(setGenre);
    JSBIND_PFUNCTION(getAlbumArtist);
    JSBIND_PFUNCTION(setAlbumArtist);
    JSBIND_PFUNCTION(getComposer);
    JSBIND_PFUNCTION(setComposer);
    JSBIND_PFUNCTION(getLyricist);
    JSBIND_PFUNCTION(setLyricist);
    JSBIND_PFUNCTION(getComment);
    JSBIND_PFUNCTION(setComment);
    JSBIND_PFUNCTION(getLyrics);
    JSBIND_PFUNCTION(setLyrics);
    JSBIND_PFUNCTION(getCover);
    JSBIND_PFUNCTION(setCover);
    JSBIND_PFUNCTION(init_libass);
    JSBIND_PFUNCTION(get_png_data_at_time);
    JSBIND_FUNCTION(cleanup_libass);
}
