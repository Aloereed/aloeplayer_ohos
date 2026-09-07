// Independent subtitle plane for OHCodec direct HDR output. No video pixels
// cross this interface. Loading runs off the UI thread and is cancellable.
#include <ass/ass.h>
extern "C" {
#include <libavformat/avformat.h>
#include <libavutil/mathematics.h>
}
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {
struct Overlay {
    std::atomic<bool> cancelled{false};
    std::atomic<int> status{0}; // loading, ready=1, failed=-1
    std::mutex mutex;
    ASS_Library *library = nullptr;
    ASS_Renderer *renderer = nullptr;
    ASS_Track *track = nullptr;
    std::vector<uint8_t> pixels;
    std::chrono::steady_clock::time_point deadline;
    ~Overlay() {
        if (track) ass_free_track(track);
        if (renderer) ass_renderer_done(renderer);
        if (library) ass_library_done(library);
    }
};
using Handle = std::shared_ptr<Overlay>;
int interrupted(void *opaque) {
    auto *o = static_cast<Overlay *>(opaque);
    return o->cancelled || std::chrono::steady_clock::now() > o->deadline;
}
void load(const Handle &o, const std::string &uri, int index, const std::string &headers) {
    const bool external = index < 0;
    AVFormatContext *input = avformat_alloc_context();
    if (!input) { o->status = -1; return; }
    o->deadline = std::chrono::steady_clock::now() + std::chrono::seconds(25);
    input->interrupt_callback = {interrupted, o.get()};
    AVDictionary *options = nullptr;
    av_dict_set(&options, "rw_timeout", "8000000", 0);
    if (!headers.empty()) av_dict_set(&options, "headers", headers.c_str(), 0);
    int result = avformat_open_input(&input, uri.c_str(), nullptr, &options);
    av_dict_free(&options);
    if (result < 0) { if (input) avformat_close_input(&input); o->status = -1; return; }
    if (avformat_find_stream_info(input, nullptr) < 0) {
        avformat_close_input(&input); o->status = -1; return;
    }
    if (index < 0) {
        for (unsigned i = 0; i < input->nb_streams; ++i) {
            if (input->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) { index = i; break; }
        }
    }
    if (index < 0 || unsigned(index) >= input->nb_streams ||
        (input->streams[index]->codecpar->codec_id != AV_CODEC_ID_ASS &&
         input->streams[index]->codecpar->codec_id != AV_CODEC_ID_SSA)) {
        avformat_close_input(&input); o->status = -1; return;
    }
    o->library = ass_library_init();
    if (!o->library) { avformat_close_input(&input); o->status = -1; return; }
    ass_set_extract_fonts(o->library, 1);
    size_t fontBytes = 0;
    for (unsigned i = 0; i < input->nb_streams; ++i) {
        auto *par = input->streams[i]->codecpar;
        if (par->codec_type != AVMEDIA_TYPE_ATTACHMENT || par->extradata_size <= 0) continue;
        auto *name = av_dict_get(input->streams[i]->metadata, "filename", nullptr, 0);
        if (!name || (par->codec_id != AV_CODEC_ID_TTF && par->codec_id != AV_CODEC_ID_OTF)) continue;
        fontBytes += par->extradata_size;
        if (fontBytes > 32 * 1024 * 1024) break;
        ass_add_font(o->library, name->value, reinterpret_cast<char *>(par->extradata), par->extradata_size);
    }
    o->renderer = ass_renderer_init(o->library);
    o->track = ass_new_track(o->library);
    if (!o->renderer || !o->track) { avformat_close_input(&input); o->status = -1; return; }
    // System fallback plus container font attachments. Preserve authored styles.
    ass_set_fonts(o->renderer, "/system/fonts/HarmonyOS_Sans_SC.ttf", "HarmonyOS Sans SC",
                  ASS_FONTPROVIDER_AUTODETECT, nullptr, 1);
    auto *stream = input->streams[index];
    ass_process_codec_private(o->track, reinterpret_cast<char *>(stream->codecpar->extradata),
                              stream->codecpar->extradata_size);
    AVPacket *packet = av_packet_alloc();
    size_t bytes = 0;
    bool complete = false;
    const int64_t origin = external || input->start_time == AV_NOPTS_VALUE ? 0 : input->start_time / 1000;
    if (packet) while (!interrupted(o.get())) {
        result = av_read_frame(input, packet);
        if (result < 0) { complete = result == AVERROR_EOF; break; }
        if (packet->stream_index == index && packet->pts != AV_NOPTS_VALUE) {
            bytes += packet->size;
            if (bytes > 32 * 1024 * 1024 || o->track->n_events > 200000) { av_packet_unref(packet); break; }
            const auto start = av_rescale_q(packet->pts, stream->time_base, AVRational{1,1000}) - origin;
            const auto duration = av_rescale_q(packet->duration, stream->time_base, AVRational{1,1000});
            ass_process_chunk(o->track, reinterpret_cast<char *>(packet->data), packet->size, start, duration);
        }
        av_packet_unref(packet);
    }
    av_packet_free(&packet);
    avformat_close_input(&input);
    o->status = complete && !o->cancelled ? 1 : -1;
}
}

extern "C" __attribute__((visibility("default"))) void *aloe_ass_open(const char *uri, int index, const char *headers) {
    try {
        auto o = std::make_shared<Overlay>();
        auto handle = std::make_unique<Handle>(o);
        std::thread(load, o, std::string(uri), index, std::string(headers)).detach();
        return handle.release();
    } catch (...) { return nullptr; }
}

extern "C" __attribute__((visibility("default"))) void aloe_ass_close(void *handle) {
    if (!handle) return;
    auto *h = static_cast<Handle *>(handle);
    (*h)->cancelled = true;
    delete h; // Worker retains ownership until interrupted; never block Flutter.
}

// Returns 0 while loading, -1 on failure, 1 for a new plane, 2 for unchanged.
// The caller owns the output buffer. Empty frames are returned to clear old text.
extern "C" __attribute__((visibility("default"))) int aloe_ass_render(
    void *handle, int64_t timeMs, int width, int height, uint8_t *out) {
    if (!handle || !out || width <= 0 || height <= 0 || width > 1920 || height > 1920) return -1;
    auto o = *static_cast<Handle *>(handle);
    if (o->status != 1) return o->status;
    ass_set_frame_size(o->renderer, width, height);
    int changed = 0;
    ASS_Image *image = ass_render_frame(o->renderer, o->track, timeMs, &changed);
    if (!changed) return 2;
    memset(out, 0, size_t(width) * height * 4);
    for (; image; image = image->next) {
        int x0 = std::max(0, -image->dst_x), y0 = std::max(0, -image->dst_y);
        int x1 = std::min(image->w, width - image->dst_x), y1 = std::min(image->h, height - image->dst_y);
        const unsigned opacity = 255 - (image->color & 255);
        const unsigned r = image->color >> 24, g = (image->color >> 16) & 255, b = (image->color >> 8) & 255;
        for (int y = y0; y < y1; ++y) for (int x = x0; x < x1; ++x) {
            const unsigned a = image->bitmap[y * image->stride + x] * opacity / 255;
            auto *dst = out + (size_t(y + image->dst_y) * width + x + image->dst_x) * 4;
            // Premultiplied source-over, matching Flutter's RGBA pixel decoder.
            dst[0] = (r * a + dst[0] * (255 - a) + 127) / 255;
            dst[1] = (g * a + dst[1] * (255 - a) + 127) / 255;
            dst[2] = (b * a + dst[2] * (255 - a) + 127) / 255;
            dst[3] = a + (dst[3] * (255 - a) + 127) / 255;
        }
    }
    return 1;
}
