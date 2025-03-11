/*
 * @Author:
 * @Date: 2025-01-21 20:39:36
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-03-10 21:14:37
 * @Description: file content
 */
#include "utils.hpp"
#include <aki/jsbind.h>
extern "C" {
#include <libavutil/log.h>
#include <libavutil/error.h>
#include <libavformat/avformat.h>
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

#include <iostream>
#include <cstdio>
#include <cstdlib>
#include <cstdarg>

#include <png.h>
// 用于保存程序状态的跳转点
sigjmp_buf jumpBuffer;

// 信号处理函数
void handleSegmentationFault(int signal) {
    std::cerr << "Segmentation fault caught! Recovering..." << std::endl;
    // 跳转到保存的程序状态
    siglongjmp(jumpBuffer, 1);
}

std::string type_audio = "normal";
std::string toUTF8(const std::wstring &wstr) {
    std::wstring_convert<std::codecvt_utf8<wchar_t>> converter;
    return converter.to_bytes(wstr);
}

int64_t get_video_duration(const std::string &file_path) {
    // 初始化libavformat，并注册所有的muxers/demuxers
    // av_register_all();

    AVFormatContext *format_ctx = nullptr;

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
    return duration / 1000;
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


TagLib::File *openFile(const std::string &filename) {
    // 使用 TagLib::FileRef 自动检测文件类型
    TagLib::FileRef fileRef(filename.c_str());

    if (!fileRef.isNull() && fileRef.file()) {
        // 动态转换为具体的文件类型
        if (filename.find(".mp3") != std::string::npos) {
            type_audio = "mp3";
            return new TagLib::MPEG::File(filename.c_str());
        } else if (filename.find(".flac") != std::string::npos) {
            type_audio = "flac";
            return new TagLib::FLAC::File(filename.c_str());
        } else if (filename.find(".ogg") != std::string::npos) {
            type_audio = "ogg";
            return new TagLib::Ogg::Vorbis::File(filename.c_str());
        } else if (filename.find(".m4a") != std::string::npos || filename.find(".aac") != std::string::npos) {
            type_audio = "m4a";
            return new TagLib::MP4::File(filename.c_str());
        } else {
            type_audio = "normal";
            return nullptr;
        }
    }

    // 如果文件类型不支持，返回 nullptr
    return nullptr;
}

// 读取标题
std::string getTitle(const std::string &filename) {
    auto file = openFile(filename);
    if (!file)
        return "";
    std::string title = file->tag()->title().to8Bit(true);
    delete file;
    return title;
}

// 写入标题
void setTitle(const std::string &filename, const std::string &title) {
    auto file = openFile(filename);
    if (!file)
        return;
    std::wstring wTitle = fromUTF8(title);
    file->tag()->setTitle(wTitle);
    file->save();
    delete file;
}

// 读取艺术家
std::string getArtist(const std::string &filename) {
    auto file = openFile(filename);
    if (!file)
        return "";
    std::string artist = file->tag()->artist().to8Bit(true);
    delete file;
    return artist;
}

// 写入艺术家
void setArtist(const std::string &filename, const std::string &artist) {
    auto file = openFile(filename);
    if (!file)
        return;
    std::wstring wArtist = fromUTF8(artist);
    file->tag()->setArtist(wArtist);
    file->save();
    delete file;
}

// 读取专辑
std::string getAlbum(const std::string &filename) {
    auto file = openFile(filename);
    if (!file)
        return "";
    std::string album = file->tag()->album().to8Bit(true);
    delete file;
    return album;
}

// 写入专辑
void setAlbum(const std::string &filename, const std::string &album) {
    auto file = openFile(filename);
    if (!file)
        return;
    std::wstring wAlbum = fromUTF8(album);
    file->tag()->setAlbum(wAlbum);
    file->save();
    delete file;
}

// 读取年份
int getYear(const std::string &filename) {
    auto file = openFile(filename);
    if (!file)
        return 0;
    int year = file->tag()->year();
    delete file;
    return year;
}

// 写入年份
void setYear(const std::string &filename, int year) {
    auto file = openFile(filename);
    if (!file)
        return;
    file->tag()->setYear(year);
    file->save();
    delete file;
}

// 读取音轨号
int getTrack(const std::string &filename) {
    auto file = openFile(filename);
    if (!file)
        return 0;
    int track = file->tag()->track();
    delete file;
    return track;
}

// 写入音轨号
void setTrack(const std::string &filename, int track) {
    auto file = openFile(filename);
    if (!file)
        return;
    file->tag()->setTrack(track);
    file->save();
    delete file;
}

// 读取风格
std::string getGenre(const std::string &filename) {
    auto file = openFile(filename);
    if (!file)
        return "";
    std::string genre = file->tag()->genre().to8Bit(true);
    delete file;
    return genre;
}

// 写入风格
void setGenre(const std::string &filename, const std::string &genre) {
    auto file = openFile(filename);
    if (!file)
        return;
    std::wstring wGenre = fromUTF8(genre);
    file->tag()->setGenre(wGenre);
    file->save();
    delete file;
}

// 读取注释
std::string getComment(const std::string &filename) {
    auto file = openFile(filename);
    if (!file)
        return "";
    std::string comment = file->tag()->comment().to8Bit(true);
    delete file;
    return comment;
}

// 写入注释
void setComment(const std::string &filename, const std::string &comment) {
    auto file = openFile(filename);
    if (!file)
        return;
    std::wstring wComment = fromUTF8(comment);
    file->tag()->setComment(wComment);
    file->save();
    delete file;
}

// 读取作曲
std::string getComposer(const std::string &filename) {
    TagLib::FileRef fileRef(filename.c_str());

    if (!fileRef.isNull() && fileRef.file()) {
        // 动态转换为具体的文件类型
        if (type_audio == "mp3") {
            TagLib::MPEG::File *file = (TagLib::MPEG::File *)openFile(filename);
            if (!file)
                return "";
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return "";
            auto frame = tag->frameList("TCOM").front();
            if (!frame)
                return "";
            std::string composer = frame->toString().to8Bit(true);
            delete file;
            return composer;
        } else if (type_audio == "flac") {
            TagLib::FLAC::File *file = (TagLib::FLAC::File *)openFile(filename);
            if (!file)
                return "";
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return "";
            auto frame = tag->frameList("TCOM").front();
            if (!frame)
                return "";
            std::string composer = frame->toString().to8Bit(true);
            delete file;
            return composer;
        }
    } else {
        return "";
    }
}

// 写入作曲
void setComposer(const std::string &filename, const std::string &composer) {
    TagLib::FileRef fileRef(filename.c_str());

    if (!fileRef.isNull() && fileRef.file()) {
        if (type_audio == "mp3") {
            TagLib::MPEG::File *file = (TagLib::MPEG::File *)openFile(filename);
            if (!file)
                return;
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return;
            auto frame = TagLib::ID3v2::UserTextIdentificationFrame::find(tag, "TCOM");
            if (!frame) {
                frame = new TagLib::ID3v2::UserTextIdentificationFrame("TCOM");
                tag->addFrame(frame);
            }
            std::wstring wComposer = fromUTF8(composer);
            frame->setText(wComposer);
            file->save();
            delete file;
        } else if (type_audio == "flac") {
            TagLib::FLAC::File *file = (TagLib::FLAC::File *)openFile(filename);
            if (!file)
                return;
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return;
            auto frame = TagLib::ID3v2::UserTextIdentificationFrame::find(tag, "TCOM");
            if (!frame) {
                frame = new TagLib::ID3v2::UserTextIdentificationFrame("TCOM");
                tag->addFrame(frame);
            }
            std::wstring wComposer = fromUTF8(composer);
            frame->setText(wComposer);
            file->save();
            delete file;
        }
    }
}

// 读取作词
std::string getLyricist(const std::string &filename) {
    TagLib::FileRef fileRef(filename.c_str());

    if (!fileRef.isNull() && fileRef.file()) {
        if (type_audio == "mp3") {
            TagLib::MPEG::File *file = (TagLib::MPEG::File *)openFile(filename);
            if (!file)
                return "";
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return "";
            auto frame = tag->frameList("TEXT").front();
            if (!frame)
                return "";
            std::string lyricist = frame->toString().to8Bit(true);
            delete file;
            return lyricist;
        } else if (type_audio == "flac") {
            TagLib::FLAC::File *file = (TagLib::FLAC::File *)openFile(filename);
            if (!file)
                return "";
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return "";
            auto frame = tag->frameList("TEXT").front();
            if (!frame)
                return "";
            std::string lyricist = frame->toString().to8Bit(true);
            delete file;
            return lyricist;
        }
    }
    return "";
}

// 写入作词
void setLyricist(const std::string &filename, const std::string &lyricist) {
    TagLib::FileRef fileRef(filename.c_str());

    if (!fileRef.isNull() && fileRef.file()) {
        if (type_audio == "mp3") {
            TagLib::MPEG::File *file = (TagLib::MPEG::File *)openFile(filename);
            if (!file)
                return;
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return;
            auto frame = TagLib::ID3v2::UserTextIdentificationFrame::find(tag, "TEXT");
            if (!frame) {
                frame = new TagLib::ID3v2::UserTextIdentificationFrame("TEXT");
                tag->addFrame(frame);
            }
            std::wstring wLyricist = fromUTF8(lyricist);
            frame->setText(wLyricist);
            file->save();
            delete file;
        } else if (type_audio == "flac") {
            TagLib::FLAC::File *file = (TagLib::FLAC::File *)openFile(filename);
            if (!file)
                return;
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return;
            auto frame = TagLib::ID3v2::UserTextIdentificationFrame::find(tag, "TEXT");
            if (!frame) {
                frame = new TagLib::ID3v2::UserTextIdentificationFrame("TEXT");
                tag->addFrame(frame);
            }
            std::wstring wLyricist = fromUTF8(lyricist);
            frame->setText(wLyricist);
            file->save();
            delete file;
        }
    }
}


// 读取碟号
int getDisc(const std::string &filename) {
    TagLib::FileRef fileRef(filename.c_str());

    if (!fileRef.isNull() && fileRef.file()) {
        if (type_audio == "mp3") {
            TagLib::MPEG::File *file = (TagLib::MPEG::File *)openFile(filename);
            if (!file)
                return 0;
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return 0;
            auto frameList = tag->frameList("TPOS");
            if (frameList.isEmpty())
                return 0;
            auto frame = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame *>(frameList.front());
            if (!frame)
                return 0;
            int disc = frame->toString().toInt();
            delete file;
            return disc;
        } else if (type_audio == "flac") {
            TagLib::FLAC::File *file = (TagLib::FLAC::File *)openFile(filename);
            if (!file)
                return 0;
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return 0;
            auto frameList = tag->frameList("TPOS");
            if (frameList.isEmpty())
                return 0;
            auto frame = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame *>(frameList.front());
            if (!frame)
                return 0;
            int disc = frame->toString().toInt();
            delete file;
            return disc;
        }
    }
    return 0;
}

// 写入碟号
void setDisc(const std::string &filename, int disc) {
    TagLib::FileRef fileRef(filename.c_str());

    if (!fileRef.isNull() && fileRef.file()) {
        if (type_audio == "mp3") {
            TagLib::MPEG::File *file = (TagLib::MPEG::File *)openFile(filename);
            if (!file)
                return;
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return;
            auto frameList = tag->frameList("TPOS");
            TagLib::ID3v2::UserTextIdentificationFrame *frame = nullptr;
            if (!frameList.isEmpty()) {
                frame = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame *>(frameList.front());
            }
            if (!frame) {
                frame = new TagLib::ID3v2::UserTextIdentificationFrame("TPOS");
                tag->addFrame(frame);
            }
            frame->setText(TagLib::String::number(disc));
            file->save();
            delete file;
        } else if (type_audio == "flac") {
            TagLib::FLAC::File *file = (TagLib::FLAC::File *)openFile(filename);
            if (!file)
                return;
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return;
            auto frameList = tag->frameList("TPOS");
            TagLib::ID3v2::UserTextIdentificationFrame *frame = nullptr;
            if (!frameList.isEmpty()) {
                frame = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame *>(frameList.front());
            }
            if (!frame) {
                frame = new TagLib::ID3v2::UserTextIdentificationFrame("TPOS");
                tag->addFrame(frame);
            }
            frame->setText(TagLib::String::number(disc));
            file->save();
            delete file;
        }
    }
}

// 读取专辑艺术家
std::string getAlbumArtist(const std::string &filename) {
    TagLib::FileRef fileRef(filename.c_str());

    if (!fileRef.isNull() && fileRef.file()) {
        if (type_audio == "mp3") {
            TagLib::MPEG::File *file = (TagLib::MPEG::File *)openFile(filename);
            if (!file)
                return "";
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return "";
            auto frameList = tag->frameList("TPE2");
            if (frameList.isEmpty())
                return "";
            auto frame = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame *>(frameList.front());
            if (!frame)
                return "";
            std::string albumArtist = frame->toString().to8Bit(true);
            delete file;
            return albumArtist;
        } else if (type_audio == "flac") {
            TagLib::FLAC::File *file = (TagLib::FLAC::File *)openFile(filename);
            if (!file)
                return "";
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return "";
            auto frameList = tag->frameList("TPE2");
            if (frameList.isEmpty())
                return "";
            auto frame = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame *>(frameList.front());
            if (!frame)
                return "";
            std::string albumArtist = frame->toString().to8Bit(true);
            delete file;
            return albumArtist;
        }
    }
    return "";
}

// 写入专辑艺术家
void setAlbumArtist(const std::string &filename, const std::string &albumArtist) {
    TagLib::FileRef fileRef(filename.c_str());

    if (!fileRef.isNull() && fileRef.file()) {
        if (type_audio == "mp3") {
            TagLib::MPEG::File *file = (TagLib::MPEG::File *)openFile(filename);
            if (!file)
                return;
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return;
            auto frameList = tag->frameList("TPE2");
            TagLib::ID3v2::UserTextIdentificationFrame *frame = nullptr;
            if (!frameList.isEmpty()) {
                frame = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame *>(frameList.front());
            }
            if (!frame) {
                frame = new TagLib::ID3v2::UserTextIdentificationFrame("TPE2");
                tag->addFrame(frame);
            }
            std::wstring wAlbumArtist = fromUTF8(albumArtist);
            frame->setText(wAlbumArtist);
            file->save();
            delete file;
        } else if (type_audio == "flac") {
            TagLib::FLAC::File *file = (TagLib::FLAC::File *)openFile(filename);
            if (!file)
                return;
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return;
            auto frameList = tag->frameList("TPE2");
            TagLib::ID3v2::UserTextIdentificationFrame *frame = nullptr;
            if (!frameList.isEmpty()) {
                frame = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame *>(frameList.front());
            }
            if (!frame) {
                frame = new TagLib::ID3v2::UserTextIdentificationFrame("TPE2");
                tag->addFrame(frame);
            }
            std::wstring wAlbumArtist = fromUTF8(albumArtist);
            frame->setText(wAlbumArtist);
            file->save();
            delete file;
        }
    }
}

// 读取歌词
std::string getLyrics(const std::string &filename) {
    // 设置 SIGSEGV 信号处理函数
    struct sigaction sa;
    sa.sa_handler = handleSegmentationFault;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGSEGV, &sa, nullptr);
    if (sigsetjmp(jumpBuffer, 1) == 0) {
        TagLib::FileRef fileRef(filename.c_str());

        if (!fileRef.isNull() && fileRef.file()) {
            if (type_audio == "mp3") {
                TagLib::MPEG::File *file = (TagLib::MPEG::File *)openFile(filename);
                if (!file)
                    return "";
                auto tag = file->ID3v2Tag(true);
                if (!tag)
                    return "";
                auto frameList = tag->frameList("USLT");
                if (frameList.isEmpty())
                    return "";
                auto frame = dynamic_cast<TagLib::ID3v2::UnsynchronizedLyricsFrame *>(frameList.front());
                if (!frame)
                    return "";
                std::string lyrics = frame->text().to8Bit(true);
                delete file;
                return lyrics;
            } else if (type_audio == "flac") {
                TagLib::FLAC::File *file = (TagLib::FLAC::File *)openFile(filename);
                if (!file)
                    return "";
                auto tag = file->ID3v2Tag(true);
                if (!tag)
                    return "";
                auto frameList = tag->frameList("USLT");
                if (frameList.isEmpty())
                    return "";
                auto frame = dynamic_cast<TagLib::ID3v2::UnsynchronizedLyricsFrame *>(frameList.front());
                if (!frame)
                    return "";
                std::string lyrics = frame->text().to8Bit(true);
                delete file;
                return lyrics;
            }
        }
    } else {
        // 从 SIGSEGV 恢复后的逻辑
        std::cout << "Recovered from segmentation fault!" << std::endl;
    }
    return "";
}

// 写入歌词
void setLyrics(const std::string &filename, const std::string &lyrics) {
    TagLib::FileRef fileRef(filename.c_str());

    if (!fileRef.isNull() && fileRef.file()) {
        if (type_audio == "mp3") {
            TagLib::MPEG::File *file = (TagLib::MPEG::File *)openFile(filename);
            if (!file)
                return;
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return;
            auto frameList = tag->frameList("USLT");
            TagLib::ID3v2::UnsynchronizedLyricsFrame *frame = nullptr;
            if (!frameList.isEmpty()) {
                frame = dynamic_cast<TagLib::ID3v2::UnsynchronizedLyricsFrame *>(frameList.front());
            }
            if (!frame) {
                frame = new TagLib::ID3v2::UnsynchronizedLyricsFrame;
                frame->setDescription("Lyrics");
                frame->setLanguage("eng");
                tag->addFrame(frame);
            }
            std::wstring wLyrics = fromUTF8(lyrics);
            frame->setText(wLyrics);
            file->save();
            delete file;
        } else if (type_audio == "flac") {
            TagLib::FLAC::File *file = (TagLib::FLAC::File *)openFile(filename);
            if (!file)
                return;
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return;
            auto frameList = tag->frameList("USLT");
            TagLib::ID3v2::UnsynchronizedLyricsFrame *frame = nullptr;
            if (!frameList.isEmpty()) {
                frame = dynamic_cast<TagLib::ID3v2::UnsynchronizedLyricsFrame *>(frameList.front());
            }
            if (!frame) {
                frame = new TagLib::ID3v2::UnsynchronizedLyricsFrame;
                frame->setDescription("Lyrics");
                frame->setLanguage("eng");
                tag->addFrame(frame);
            }
            std::wstring wLyrics = fromUTF8(lyrics);
            frame->setText(wLyrics);
            file->save();
            delete file;
        }
    }
}

// 读取封面
std::string getCover(const std::string &filename) {
    TagLib::FileRef fileRef(filename.c_str());

    if (!fileRef.isNull() && fileRef.file()) {
        if (type_audio == "mp3") {
            TagLib::MPEG::File *file = (TagLib::MPEG::File *)openFile(filename);
            if (!file)
                return "";
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return "";
            auto frameList = tag->frameList("APIC");
            if (frameList.isEmpty())
                return "";
            auto frame = dynamic_cast<TagLib::ID3v2::AttachedPictureFrame *>(frameList.front());
            if (!frame)
                return "";
            auto pictureData = frame->picture();
            std::string base64Data = "data:" + frame->mimeType().to8Bit(true) + ";base64," +
                                     std::string(pictureData.toBase64().data(), pictureData.toBase64().size());
            delete file;
            return base64Data;
        } else if (type_audio == "flac") {
            TagLib::FLAC::File *file = (TagLib::FLAC::File *)openFile(filename);
            if (!file)
                return "";
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return "";
            auto frameList = tag->frameList("APIC");
            if (frameList.isEmpty())
                return "";
            auto frame = dynamic_cast<TagLib::ID3v2::AttachedPictureFrame *>(frameList.front());
            if (!frame)
                return "";
            auto pictureData = frame->picture();
            std::string base64Data = "data:" + frame->mimeType().to8Bit(true) + ";base64," +
                                     std::string(pictureData.toBase64().data(), pictureData.toBase64().size());
            delete file;
            return base64Data;
        }
    }
    return "";
}

// 写入封面
void setCover(const std::string &filename, const std::string &base64Data) {
    TagLib::FileRef fileRef(filename.c_str());

    if (!fileRef.isNull() && fileRef.file()) {
        if (type_audio == "mp3") {
            TagLib::MPEG::File *file = (TagLib::MPEG::File *)openFile(filename);
            if (!file)
                return;
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return;

            // 解析 base64 数据
            size_t commaPos = base64Data.find(',');
            if (commaPos == std::string::npos)
                return;
            std::string mimeType = base64Data.substr(5, commaPos - 5); // 提取 MIME 类型
            std::string base64 = base64Data.substr(commaPos + 1);      // 提取 base64 数据
            TagLib::ByteVector pictureData =
                TagLib::ByteVector::fromBase64(TagLib::ByteVector(base64.c_str(), base64.size()));

            // 创建封面帧
            auto frame = new TagLib::ID3v2::AttachedPictureFrame;
            frame->setMimeType(mimeType);
            frame->setPicture(pictureData);
            frame->setType(TagLib::ID3v2::AttachedPictureFrame::FrontCover);

            // 删除旧的封面帧
            auto oldFrames = tag->frameList("APIC");
            for (auto oldFrame : oldFrames) {
                tag->removeFrame(oldFrame);
            }

            // 添加新的封面帧
            tag->addFrame(frame);
            file->save();
            delete file;
        } else if (type_audio == "flac") {
            TagLib::FLAC::File *file = (TagLib::FLAC::File *)openFile(filename);
            if (!file)
                return;
            auto tag = file->ID3v2Tag(true);
            if (!tag)
                return;

            // 解析 base64 数据
            size_t commaPos = base64Data.find(',');
            if (commaPos == std::string::npos)
                return;
            std::string mimeType = base64Data.substr(5, commaPos - 5); // 提取 MIME 类型
            std::string base64 = base64Data.substr(commaPos + 1);      // 提取 base64 数据
            TagLib::ByteVector pictureData =
                TagLib::ByteVector::fromBase64(TagLib::ByteVector(base64.c_str(), base64.size()));

            // 创建封面帧
            auto frame = new TagLib::ID3v2::AttachedPictureFrame;
            frame->setMimeType(mimeType);
            frame->setPicture(pictureData);
            frame->setType(TagLib::ID3v2::AttachedPictureFrame::FrontCover);

            // 删除旧的封面帧
            auto oldFrames = tag->frameList("APIC");
            for (auto oldFrame : oldFrames) {
                tag->removeFrame(oldFrame);
            }

            // 添加新的封面帧
            tag->addFrame(frame);
            file->save();
            delete file;
        }
    }
}


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
