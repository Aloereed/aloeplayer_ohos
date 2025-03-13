# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(ohos)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
# 启用c++17
set(CMAKE_CXX_STANDARD 17)
if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()
set(AKI_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../../oh_modules/@ohos/aki) # 设置AKI根路径

set(CMAKE_MODULE_PATH ${AKI_ROOT_PATH})
find_package(Aki REQUIRED)
include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include
                    ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/taglib/arm64-v8a/include)
# add_library(avcodec SHARED IMPORTED)
# set_target_properties(avcodec
#     PROPERTIES
#     IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/${OHOS_ARCH}/lib/libavcodec.so)

# add_library(avformat SHARED IMPORTED)
# set_target_properties(avformat
#     PROPERTIES
#     IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/${OHOS_ARCH}/lib/libavformat.so)
# add_library(avutil SHARED IMPORTED)
# set_target_properties(avutil
#         PROPERTIES
#         IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/${OHOS_ARCH}/lib/libavutil.so)
# add_library(avdevice SHARED IMPORTED)
# set_target_properties(avdevice
#         PROPERTIES
#         IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/${OHOS_ARCH}/lib/libavdevice.so)
# add_library(swresample SHARED IMPORTED)
# set_target_properties(swresample
#         PROPERTIES
#         IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/${OHOS_ARCH}/lib/libswresample.so)
# add_library(swscale SHARED IMPORTED)
# set_target_properties(swscale
#         PROPERTIES
#         IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/${OHOS_ARCH}/lib/libswscale.so)
# add_library(avfilter SHARED IMPORTED)
# set_target_properties(avfilter
#         PROPERTIES
#         IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/${OHOS_ARCH}/lib/libavfilter.so)
add_library(taglib STATIC IMPORTED)
set_target_properties(taglib
        PROPERTIES
        IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/taglib/${OHOS_ARCH}/lib/libtag.a
        INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/taglib/arm64-v8a/include
)
# add_library(libpng SHARED IMPORTED)
# set_target_properties(libpng
#         PROPERTIES
#         IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/libpng/${OHOS_ARCH}/lib/libpng16.so.16.39.0
#         INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_CURRENT_SOURCE_DIR}/libpng/arm64-v8a/include
# )
# add_library(libass SHARED IMPORTED)
# set_target_properties(libass
#         PROPERTIES
#         IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/libass/${OHOS_ARCH}/lib/libass.so.9
#         INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_CURRENT_SOURCE_DIR}/libass/arm64-v8a/include
# )

# 第三方库


# 创建 fftool 动态链接库
# add_library(fftool SHARED
#     cmdutils.c
#     exception.c
#     ffmpeg_filter.c
#     ffmpeg_hw.c
#     ffmpeg_opt.c
#     ffmpeg.c
#     opt_common.c
#     sync_queue.c
#     objpool.c
#     thread_queue.c
#     ffmpeg_demux.c
#     ffmpeg_mux_init.c
#     ffmpeg_mux.c
#     )

# target_link_libraries(fftool PUBLIC avcodec avformat avutil avdevice swresample swscale avfilter)

# 添加 fftool 的头文件目录
# target_include_directories(fftool PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

add_library(entry SHARED main.cpp napi_init.cpp asstest.c cmdutils.c
exception.c
ffmpeg_filter.c
ffmpeg_hw.c
ffmpeg_opt.c
ffmpeg.c
opt_common.c
sync_queue.c
objpool.c
thread_queue.c
ffmpeg_demux.c
ffmpeg_mux_init.c
ffmpeg_mux.c)
target_link_libraries(entry PUBLIC libace_napi.z.so  libhilog_ndk.z.so  Aki::libjsbind taglib libGLESv3.so libEGL.so libnative_window.so libvulkan.so)
target_compile_features(entry PRIVATE cxx_std_17)


ADD_DEFINITIONS(-DVK_USE_PLATFORM_OHOS=1)
ADD_DEFINITIONS(-DEGL_EGLEXT_PROTOTYPES)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libalsa/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/brotli/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/bzip2/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/check/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libfdk-aac/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/fftw3/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/fontconfig/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/freetype2/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/frei0r/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/fribidi/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/gdbm/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/gettext/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/giflib/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/gmp/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/harfbuzz/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/helper.py/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/json-c/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/lcms2/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libaom/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libass/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libatomic_ops/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libcodec2/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libdav1d/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libdovi/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libgme/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libiconv/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libjpeg-turbo/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libkvazaar/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libmysofa/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libopus/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libplacebo/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libpng/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/librav1e/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libshine/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libsndfile/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libudfread/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libvmaf/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libvpx/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libwebp/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libxevd/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libxeve/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libxml2/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libzip/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/lilv/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/lv2/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/mpv/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/openal-soft/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/openjpeg/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/openmp/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/openssl3/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/pulseaudio/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/serd/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/shaderc/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/sord/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/speexdsp/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/sratom/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/uchardet/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/vid.stab/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/vvenc/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/x264/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/x265/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/xvidcore/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/xxhash/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/xz/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/zix/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/zlib/arm64-v8a/include)
target_include_directories(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/zstd/arm64-v8a/include)

target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libalsa/arm64-v8a/lib/libasound.so.2)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/brotli/arm64-v8a/lib/libbrotlicommon-static.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/brotli/arm64-v8a/lib/libbrotlidec-static.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/brotli/arm64-v8a/lib/libbrotlienc-static.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/bzip2/arm64-v8a/lib/libbz2.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/check/arm64-v8a/lib/libcheck.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libfdk-aac/arm64-v8a/lib/libfdk-aac.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/arm64-v8a/lib/libavcodec.so.61)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/arm64-v8a/lib/libavdevice.so.61)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/arm64-v8a/lib/libavfilter.so.10)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/arm64-v8a/lib/libavformat.so.61)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/arm64-v8a/lib/libavutil.so.59)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/arm64-v8a/lib/libpostproc.so.58)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/arm64-v8a/lib/libswresample.so.5)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/arm64-v8a/lib/libswscale.so.8)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/fftw3/arm64-v8a/lib/libfftw3f.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/fontconfig/arm64-v8a/lib/libfontconfig.so.1)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/freetype2/arm64-v8a/lib/libfreetype.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/fribidi/arm64-v8a/lib/libfribidi.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/gdbm/arm64-v8a/lib/libgdbm.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/gettext/arm64-v8a/lib/libintl.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/giflib/arm64-v8a/lib/libgif.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/gmp/arm64-v8a/lib/libgmp.so.10)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/harfbuzz/arm64-v8a/lib/libharfbuzz.so.0)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/json-c/arm64-v8a/lib/libjson-c.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/lcms2/arm64-v8a/lib/liblcms2.so.2)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libaom/arm64-v8a/lib/libaom.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libass/arm64-v8a/lib/libass.so.9)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libatomic_ops/arm64-v8a/lib/libatomic_ops.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libcodec2/arm64-v8a/lib/libcodec2.so.0.9)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libdav1d/arm64-v8a/lib/libdav1d.so.7)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libdovi/arm64-v8a/libdovi.so.3)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libgme/arm64-v8a/lib/libgme.so.0)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libiconv/arm64-v8a/lib/libiconv.so.2)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libiconv/arm64-v8a/lib/libcharset.so.1)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libjpeg-turbo/arm64-v8a/lib/libjpeg.so.62)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libjpeg-turbo/arm64-v8a/lib/libturbojpeg.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libkvazaar/arm64-v8a/lib/libkvazaar.so.7)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libmysofa/arm64-v8a/lib/libmysofa.so.1)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libopus/arm64-v8a/lib/libopus.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libplacebo/arm64-v8a/lib/libplacebo.so.350)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libpng/arm64-v8a/lib/libpng.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/librav1e/arm64-v8a/librav1e.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libsndfile/arm64-v8a/lib/libsndfile.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libudfread/arm64-v8a/lib/libudfread.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libvmaf/arm64-v8a/lib/libvmaf.so.3)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libvpx/arm64-v8a/lib/libvpx.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libwebp/arm64-v8a/lib/libwebp.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libwebp/arm64-v8a/lib/libsharpyuv.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libwebp/arm64-v8a/lib/libwebpdecoder.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libwebp/arm64-v8a/lib/libwebpdemux.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libwebp/arm64-v8a/lib/libwebpmux.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libxevd/arm64-v8a/lib/libxevd.so.0)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libxeve/arm64-v8a/lib/libxeve.so.0)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libxml2/arm64-v8a/lib/libxml2.so)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/libzip/arm64-v8a/lib/libzip.so.5)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/lilv/arm64-v8a/lib/liblilv-0.so.0)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/mpv/arm64-v8a/lib/libmpv.so.2)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/openal-soft/arm64-v8a/lib/libopenal.so.1)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/openjpeg/arm64-v8a/lib/libopenjp2.so.7)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/openssl3/arm64-v8a/lib/libssl.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/openssl3/arm64-v8a/lib/libcrypto.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/pulseaudio/arm64-v8a/lib/libpulse.so.0)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/pulseaudio/arm64-v8a/lib/pulseaudio/libpulsecommon-16.1.so)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/serd/arm64-v8a/lib/libserd-0.so.0)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/sord/arm64-v8a/lib/libsord-0.so.0)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/shaderc/arm64-v8a/lib/libshaderc_shared.so.1)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/speexdsp/arm64-v8a/lib/libspeexdsp.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/sratom/arm64-v8a/lib/libsratom-0.so.0)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/uchardet/arm64-v8a/lib/libuchardet.so.0)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/vid.stab/arm64-v8a/lib/libvidstab.so.1.2)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/vvenc/arm64-v8a/lib/libvvenc.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/x264/arm64-v8a/lib/libx264.so.164)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/x265/arm64-v8a/lib/libx265.so.215)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/x265/arm64-v8a/lib/libx265_main10.so.215)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/x265/arm64-v8a/lib/libx265_main12.so.215)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/xvidcore/arm64-v8a/lib/libxvidcore.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/xxhash/arm64-v8a/lib/libxxhash.a)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/xz/arm64-v8a/lib/liblzma.so.5)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/zix/arm64-v8a/lib/libzix-0.so.0)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/zlib/arm64-v8a/lib/libz.so.1)
target_link_libraries(entry PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/zstd/arm64-v8a/lib/libzstd.so.1)