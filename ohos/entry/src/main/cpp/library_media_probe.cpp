#include "library_media_probe.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cerrno>
#include <cstring>
#include <vector>
#include <unistd.h>
#include <sys/stat.h>
#include <png.h>
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/base64.h>
#include <libavutil/display.h>
#include <libswscale/swscale.h>
}

namespace {
// Custom I/O keeps document-provider permission in fs.open. No assumption that
// a file://docs URI can be opened by FFmpeg's file protocol, no shared seek offset.
struct Input {
    int fd;
    int64_t offset = 0;
    int64_t bytesRead = 0;
    const std::chrono::steady_clock::time_point deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(10);
    AVFormatContext* format = nullptr;
    AVIOContext* io = nullptr;
    explicit Input(int descriptor) : fd(descriptor) {}
    ~Input() {
        if (format) avformat_close_input(&format);
        if (io) { av_freep(&io->buffer); avio_context_free(&io); }
    }
    bool expired() const {
        return bytesRead >= 64 * 1024 * 1024 || std::chrono::steady_clock::now() >= deadline;
    }
    static int interrupt(void* opaque) { return static_cast<Input*>(opaque)->expired(); }
    static int read(void* opaque, uint8_t* buffer, int size) {
        auto* input = static_cast<Input*>(opaque);
        if (input->expired()) return AVERROR_EXIT;
        const auto count = pread(input->fd, buffer, size, input->offset);
        if (count < 0) return AVERROR(errno);
        if (count == 0) return AVERROR_EOF;
        input->offset += count;
        input->bytesRead += count;
        return static_cast<int>(count);
    }
    static int64_t seek(void* opaque, int64_t offset, int whence) {
        auto* input = static_cast<Input*>(opaque);
        struct stat info{};
        if (fstat(input->fd, &info) != 0) return AVERROR(errno);
        if (whence == AVSEEK_SIZE) return info.st_size;
        whence &= ~AVSEEK_FORCE;
        int64_t base = 0;
        if (whence == SEEK_CUR) base = input->offset;
        else if (whence == SEEK_END) base = info.st_size;
        else if (whence != SEEK_SET) return AVERROR(EINVAL);
        if ((offset > 0 && base > INT64_MAX - offset) ||
            (offset < 0 && offset < -base)) return AVERROR(EINVAL);
        input->offset = base + offset;
        return input->offset;
    }
    bool open() {
        auto* buffer = static_cast<uint8_t*>(av_malloc(32768));
        if (!buffer) return false;
        io = avio_alloc_context(buffer, 32768, 0, this, read, nullptr, seek);
        if (!io) { av_free(buffer); return false; }
        format = avformat_alloc_context();
        if (!format) return false;
        format->pb = io;
        format->flags |= AVFMT_FLAG_CUSTOM_IO;
        format->interrupt_callback = {interrupt, this};
        format->probesize = 2 * 1024 * 1024;
        format->max_analyze_duration = 2 * AV_TIME_BASE;
        return avformat_open_input(&format, nullptr, nullptr, nullptr) >= 0 &&
            avformat_find_stream_info(format, nullptr) >= 0;
    }
};

struct FrameDecoder {
    AVCodecContext* codec = nullptr;
    AVFrame* frame = av_frame_alloc();
    AVPacket* packet = av_packet_alloc();
    ~FrameDecoder() {
        avcodec_free_context(&codec);
        av_frame_free(&frame);
        av_packet_free(&packet);
    }
};

std::string encodeFrame(AVFrame* frame, AVStream* stream) {
    if (frame->width <= 0 || frame->height <= 0 || frame->width > 8192 || frame->height > 8192) return "";
    AVRational sar = frame->sample_aspect_ratio;
    if (sar.num <= 0 || sar.den <= 0) sar = stream->sample_aspect_ratio;
    double aspect = static_cast<double>(frame->width) / frame->height;
    if (sar.num > 0 && sar.den > 0) aspect *= av_q2d(sar);
    if (!std::isfinite(aspect) || aspect < 0.05 || aspect > 20) return "";
    int width = aspect >= 1 ? 320 : std::max(1, static_cast<int>(320 * aspect));
    int height = aspect >= 1 ? std::max(1, static_cast<int>(320 / aspect)) : 320;
    std::vector<uint8_t> rgb(width * height * 3);
    auto* scaler = sws_getContext(frame->width, frame->height, static_cast<AVPixelFormat>(frame->format),
        width, height, AV_PIX_FMT_RGB24, SWS_BILINEAR, nullptr, nullptr, nullptr);
    if (!scaler) return "";
    uint8_t* planes[] = {rgb.data(), nullptr, nullptr, nullptr};
    int strides[] = {width * 3, 0, 0, 0};
    const int rows = sws_scale(scaler, frame->data, frame->linesize, 0, frame->height, planes, strides);
    sws_freeContext(scaler);
    if (rows != height) return "";

    size_t matrixSize = 0;
    const uint8_t* matrix = av_stream_get_side_data(stream, AV_PKT_DATA_DISPLAYMATRIX, &matrixSize);
    int rotation = 0;
    if (matrix && matrixSize >= 9 * sizeof(int32_t)) {
        const double angle = -av_display_rotation_get(reinterpret_cast<const int32_t*>(matrix));
        if (std::isfinite(angle)) rotation = (static_cast<int>(std::lround(angle / 90)) * 90 % 360 + 360) % 360;
    }
    if (rotation != 0) {
        const int targetWidth = rotation == 180 ? width : height;
        const int targetHeight = rotation == 180 ? height : width;
        std::vector<uint8_t> rotated(rgb.size());
        for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
            int tx = rotation == 90 ? height - 1 - y : rotation == 180 ? width - 1 - x : y;
            int ty = rotation == 90 ? x : rotation == 180 ? height - 1 - y : width - 1 - x;
            std::memcpy(&rotated[(ty * targetWidth + tx) * 3], &rgb[(y * width + x) * 3], 3);
        }
        rgb.swap(rotated); width = targetWidth; height = targetHeight;
    }
    png_image png{};
    png.version = PNG_IMAGE_VERSION;
    png.width = width; png.height = height; png.format = PNG_FORMAT_RGB;
    png_alloc_size_t size = 0;
    if (!png_image_write_to_memory(&png, nullptr, &size, 0, rgb.data(), 0, nullptr)) {
        png_image_free(&png); return "";
    }
    std::vector<uint8_t> encoded(size);
    const bool written = png_image_write_to_memory(&png, encoded.data(), &size, 0, rgb.data(), 0, nullptr) != 0;
    png_image_free(&png);
    if (!written) return "";
    std::vector<char> base64(AV_BASE64_SIZE(size));
    if (!av_base64_encode(base64.data(), base64.size(), encoded.data(), size)) return "";
    return std::string(base64.data());
}
} // namespace

int64_t probeDurationFd(int fd) {
    Input input(fd);
    if (!input.open()) return 0;
    const int64_t duration = input.format->duration;
    return duration == AV_NOPTS_VALUE || duration < 0 ? 0 : duration / 1000;
}

std::string probeHdrFd(int fd) {
    Input input(fd);
    if (!input.open()) return "{\"isHDR\":false}";
    bool hdr = false;
    for (unsigned i = 0; i < input.format->nb_streams; ++i) {
        const AVStream* stream = input.format->streams[i];
        const AVCodecParameters* p = stream->codecpar;
        if (p->codec_type != AVMEDIA_TYPE_VIDEO) continue;
        hdr = p->color_trc == AVCOL_TRC_SMPTE2084 || p->color_trc == AVCOL_TRC_ARIB_STD_B67;
        for (int n = 0; n < stream->nb_side_data; ++n) {
            const auto type = stream->side_data[n].type;
            if (type == AV_PKT_DATA_MASTERING_DISPLAY_METADATA || type == AV_PKT_DATA_CONTENT_LIGHT_LEVEL) hdr = true;
        }
        break;
    }
    return hdr ? "{\"isHDR\":true}" : "{\"isHDR\":false}";
}

std::string thumbnailFromFd(int fd) {
    Input input(fd);
    if (!input.open()) return "";
    const AVCodec* codec = nullptr;
    const int index = av_find_best_stream(input.format, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
    if (index < 0 || !codec) return "";
    FrameDecoder decoder;
    if (!decoder.frame || !decoder.packet) return "";
    decoder.codec = avcodec_alloc_context3(codec);
    if (!decoder.codec || avcodec_parameters_to_context(decoder.codec, input.format->streams[index]->codecpar) < 0) return "";
    decoder.codec->thread_count = 1;
    decoder.codec->max_pixels = 32 * 1024 * 1024;
    if (avcodec_open2(decoder.codec, codec, nullptr) < 0) return "";
    for (int packets = 0; packets < 500 && !input.expired(); ++packets) {
        const int read = av_read_frame(input.format, decoder.packet);
        if (read < 0) {
            avcodec_send_packet(decoder.codec, nullptr);
            if (avcodec_receive_frame(decoder.codec, decoder.frame) >= 0)
                return encodeFrame(decoder.frame, input.format->streams[index]);
            break;
        }
        if (decoder.packet->stream_index == index) {
            const int sent = avcodec_send_packet(decoder.codec, decoder.packet);
            av_packet_unref(decoder.packet);
            if (sent < 0 && sent != AVERROR(EAGAIN)) continue;
            if (avcodec_receive_frame(decoder.codec, decoder.frame) >= 0)
                return encodeFrame(decoder.frame, input.format->streams[index]);
        } else { av_packet_unref(decoder.packet); }
    }
    return "";
}
