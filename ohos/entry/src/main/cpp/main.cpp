/*
 * @Author:
 * @Date: 2025-01-21 20:39:36
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-02-11 13:43:02
 * @Description: file content
 */
#include "utils.hpp"
#include <aki/jsbind.h>
extern "C" {
#include <libavutil/log.h>
#include <libavutil/error.h>
#include <libavformat/avformat.h>
}
#include <vector>
#include <string>
#include <cstring> // for strdup
#include "hilog/log.h"
#include "napi_init.h"
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
#include <locale>
#include <codecvt>

std::string type_audio = "normal";
std::string toUTF8(const std::wstring &wstr) {
    std::wstring_convert<std::codecvt_utf8<wchar_t>> converter;
    return converter.to_bytes(wstr);
}

int64_t get_video_duration(const std::string& file_path) {
    // 初始化libavformat，并注册所有的muxers/demuxers
    // av_register_all();

    AVFormatContext* format_ctx = nullptr;

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
}
