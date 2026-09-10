#pragma once
#include <taglib/fileref.h>
#include <taglib/tpropertymap.h>
#include <taglib/mpegfile.h>
#include <taglib/flacfile.h>
#include <taglib/attachedpictureframe.h>
#include <taglib/id3v2tag.h>
#include <mutex>
#include <string>

// AKI dispatches calls on workers. Keep each file operation owned by its
// FileRef, and serialize writes against readers (including library scanning).
namespace audio_tags {
inline std::mutex mutex;
inline bool valid(TagLib::FileRef &ref) {
    if (ref.isNull() || !ref.file()->isValid() || !ref.tag()) return false;
    // TagLib can create an ID3 tag on arbitrary text bearing an .mp3 suffix.
    if (auto *mp3 = dynamic_cast<TagLib::MPEG::File *>(ref.file())) return mp3->firstFrameOffset() >= 0;
    return true;
}
inline std::string read(const std::string &path, const char *key) {
    std::lock_guard<std::mutex> lock(mutex);
    try {
        TagLib::FileRef ref(path.c_str(), false);
        if (!valid(ref)) return "";
        const auto properties = ref.file()->properties();
        const auto found = properties.find(key);
        if (found == properties.end() || found->second.isEmpty()) return "";
        return found->second.front().to8Bit(true);
    } catch (...) { return ""; }
}
inline bool write(const std::string &path, const char *key, const std::string &value) {
    std::lock_guard<std::mutex> lock(mutex);
    try {
        TagLib::FileRef ref(path.c_str(), false);
        if (!valid(ref) || ref.file()->readOnly()) return false;
        auto properties = ref.file()->properties();
        if (value.empty()) properties.erase(key);
        else properties.replace(key, TagLib::StringList(TagLib::String(value, TagLib::String::UTF8)));
        const auto rejected = ref.file()->setProperties(properties);
        if (rejected.contains(key)) return false;
        return ref.save();
    } catch (...) { return false; }
}
inline int number(const std::string &value) {
    // Disc/track tags may contain a total, e.g. 2/12.
    const auto first = value.substr(0, value.find('/'));
    try {
        size_t end = 0;
        int result = std::stoi(first, &end);
        return end == first.size() && result >= 0 ? result : 0;
    } catch (...) { return 0; }
}
}

#define AUDIO_TEXT(Name, Key) \
inline std::string get##Name(const std::string &path) { return audio_tags::read(path, Key); } \
inline bool set##Name(const std::string &path, const std::string &value) { return audio_tags::write(path, Key, value); }
AUDIO_TEXT(Title, "TITLE")
AUDIO_TEXT(Artist, "ARTIST")
AUDIO_TEXT(Album, "ALBUM")
AUDIO_TEXT(Genre, "GENRE")
AUDIO_TEXT(Comment, "COMMENT")
AUDIO_TEXT(Composer, "COMPOSER")
AUDIO_TEXT(Lyricist, "LYRICIST")
AUDIO_TEXT(AlbumArtist, "ALBUMARTIST")
AUDIO_TEXT(Lyrics, "LYRICS")
#undef AUDIO_TEXT
#define AUDIO_NUMBER(Name, Key) \
inline int get##Name(const std::string &path) { return audio_tags::number(audio_tags::read(path, Key)); } \
inline bool set##Name(const std::string &path, int value) { return value >= 0 && audio_tags::write(path, Key, value == 0 ? "" : std::to_string(value)); }
AUDIO_NUMBER(Track, "TRACKNUMBER")
AUDIO_NUMBER(Disc, "DISCNUMBER")
#undef AUDIO_NUMBER
inline int getYear(const std::string &path) {
    const auto date = audio_tags::read(path, "DATE");
    return audio_tags::number(date.substr(0, date.find('-')));
}
inline bool setYear(const std::string &path, int value) {
    return value >= 0 && audio_tags::write(path, "DATE", value == 0 ? "" : std::to_string(value));
}

inline std::string getCover(const std::string &path) {
    std::lock_guard<std::mutex> lock(audio_tags::mutex);
    try {
        TagLib::FileRef ref(path.c_str(), false);
        if (!audio_tags::valid(ref)) return "";
        TagLib::ByteVector bytes;
        if (auto *flac = dynamic_cast<TagLib::FLAC::File *>(ref.file())) {
            const auto pictures = flac->pictureList();
            if (!pictures.isEmpty()) bytes = pictures.front()->data();
        } else if (auto *mp3 = dynamic_cast<TagLib::MPEG::File *>(ref.file())) {
            auto *tag = mp3->ID3v2Tag(false);
            if (!tag) return "";
            const auto frames = tag->frameList("APIC");
            if (frames.isEmpty()) return "";
            auto *picture = dynamic_cast<TagLib::ID3v2::AttachedPictureFrame *>(frames.front());
            if (picture) bytes = picture->picture();
        }
        const auto encoded = bytes.toBase64();
        return std::string(encoded.data(), encoded.size());
    } catch (...) { return ""; }
}

inline bool setCover(const std::string &path, const std::string &data) {
    std::lock_guard<std::mutex> lock(audio_tags::mutex);
    try {
        TagLib::FileRef ref(path.c_str(), false);
        if (!audio_tags::valid(ref) || ref.file()->readOnly()) return false;
        auto comma = data.find(',');
        auto encoded = comma == std::string::npos ? data : data.substr(comma + 1);
        auto mime = comma == std::string::npos ? std::string("image/jpeg") : data.substr(5, data.find(';') - 5);
        const auto bytes = TagLib::ByteVector::fromBase64(TagLib::ByteVector(encoded.data(), encoded.size()));
        if (bytes.isEmpty()) return false;
        if (auto *flac = dynamic_cast<TagLib::FLAC::File *>(ref.file())) {
            auto *picture = new TagLib::FLAC::Picture;
            picture->setMimeType(mime);
            picture->setType(TagLib::FLAC::Picture::FrontCover);
            picture->setData(bytes);
            flac->removePictures();
            flac->addPicture(picture);
        } else if (auto *mp3 = dynamic_cast<TagLib::MPEG::File *>(ref.file())) {
            auto *tag = mp3->ID3v2Tag(true);
            if (!tag) return false;
            auto *picture = new TagLib::ID3v2::AttachedPictureFrame;
            picture->setMimeType(mime);
            picture->setType(TagLib::ID3v2::AttachedPictureFrame::FrontCover);
            picture->setPicture(bytes);
            tag->removeFrames("APIC");
            tag->addFrame(picture);
        } else { return false; }
        return ref.save();
    } catch (...) { return false; }
}
