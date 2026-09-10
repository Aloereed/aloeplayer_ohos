#include "audio_tags.h"
#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <thread>
#include <vector>
#include <chrono>

#undef assert
#define assert(condition) do { if (!(condition)) { std::cerr << "FAIL line " << __LINE__ << ": " << #condition << std::endl; std::exit(1); } } while (false)

namespace fs = std::filesystem;
int main(int argc, char **argv) try {
    std::cout << "Starting native audio tag regression" << std::endl;
    assert(argc == 3);
    fs::path fixtures(argv[1]);
    fs::path output = fs::path(argv[2]) / std::to_string(std::chrono::system_clock::now().time_since_epoch().count());
    fs::create_directories(output);
    std::vector<std::string> files;
    for (const char *name : {"xing.mp3", "sinewave.flac", "test.ogg", "alaw.wav"}) {
        auto target = output / name;
        fs::copy_file(fixtures / name, target, fs::copy_options::overwrite_existing);
        files.push_back(target.string());
    }
    for (const auto &file : files) {
        assert(setTitle(file, "中文标题"));
        assert(setArtist(file, "艺术家"));
        assert(setAlbum(file, "专辑"));
        assert(getTitle(file) == "中文标题");
        assert(getArtist(file) == "艺术家");
        assert(getAlbum(file) == "专辑");
        // Metadata editor used to call front() on absent TCOM/TEXT frames.
        assert(setComposer(file, ""));
        assert(setLyricist(file, ""));
        assert(getComposer(file).empty());
        assert(getLyricist(file).empty());
        assert(setDisc(file, 2));
        assert(setTrack(file, 3));
        assert(getDisc(file) == 2);
        assert(getTrack(file) == 3);
        assert(setLyrics(file, "第一行\n第二行"));
        assert(getLyrics(file) == "第一行\n第二行");
        assert(setComposer(file, "作曲"));
        assert(setLyricist(file, "作词"));
        assert(setAlbumArtist(file, "专辑艺术家"));
        assert(getComposer(file) == "作曲");
        assert(getLyricist(file) == "作词");
        assert(getAlbumArtist(file) == "专辑艺术家");
        assert(audio_tags::write(file, "DATE", "2026-09-10"));
        assert(getYear(file) == 2026);
        assert(getTitle(file) == "中文标题");
    }
    const auto invalid = (output / "invalid.mp3").string();
    { std::ofstream stream(invalid); stream << "not an audio file"; }
    assert(getComposer(invalid).empty());
    assert(getLyrics(invalid).empty());
    assert(!setTitle(invalid, "must fail"));
    assert(!setTitle((output / "missing.mp3").string(), "must fail"));
    assert(!setDisc(files.front(), -1));
    assert(audio_tags::number("2/12") == 2);
    assert(audio_tags::number("2147483648") == 0);
    assert(audio_tags::number("bad") == 0);
    // Mixed formats and concurrent readers/writers must not share a type tag.
    std::vector<std::thread> workers;
    for (int thread = 0; thread < 8; ++thread) workers.emplace_back([&, thread] {
        for (int repeat = 0; repeat < 100; ++repeat) {
            const auto &file = files[(thread + repeat) % files.size()];
            assert(getTitle(file) == "中文标题");
            assert(getComposer(file) == "作曲");
            assert(getLyricist(file) == "作词");
            assert(getLyrics(file) == "第一行\n第二行");
            assert(getDisc(file) == 2);
            getCover(file);
            assert(setComment(file, "并发写入"));
        }
    });
    for (auto &worker : workers) worker.join();
    std::cout << "PASS: 4 formats, absent tags, UTF-8 round trips, invalid files, 800 concurrent cycles\n";
} catch (const std::exception &error) {
    std::cerr << "FAIL: " << error.what() << std::endl;
    return 1;
}
