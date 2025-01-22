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
                    ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/${OHOS_ARCH}/include)
add_library(avcodec SHARED IMPORTED)
set_target_properties(avcodec
    PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/${OHOS_ARCH}/lib/libavcodec.so)

add_library(avformat SHARED IMPORTED)
set_target_properties(avformat
    PROPERTIES
    IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/${OHOS_ARCH}/lib/libavformat.so)
add_library(avutil SHARED IMPORTED)
set_target_properties(avutil
        PROPERTIES
        IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/${OHOS_ARCH}/lib/libavutil.so)
add_library(avdevice SHARED IMPORTED)
set_target_properties(avdevice
        PROPERTIES
        IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/${OHOS_ARCH}/lib/libavdevice.so)
add_library(swresample SHARED IMPORTED)
set_target_properties(swresample
        PROPERTIES
        IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/${OHOS_ARCH}/lib/libswresample.so)
add_library(swscale SHARED IMPORTED)
set_target_properties(swscale
        PROPERTIES
        IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/${OHOS_ARCH}/lib/libswscale.so)
add_library(avfilter SHARED IMPORTED)
set_target_properties(avfilter
        PROPERTIES
        IMPORTED_LOCATION ${CMAKE_CURRENT_SOURCE_DIR}/FFmpeg/${OHOS_ARCH}/lib/libavfilter.so)
# 创建 fftool 动态链接库
add_library(fftool SHARED
    cmdutils.c
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
    ffmpeg_mux.c
    )

target_link_libraries(fftool PUBLIC avcodec avformat avutil avdevice swresample swscale avfilter)

# 添加 fftool 的头文件目录
target_include_directories(fftool PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

add_library(entry SHARED main.cpp )
target_link_libraries(entry PUBLIC libace_napi.z.so  libhilog_ndk.z.so fftool Aki::libjsbind)
target_compile_features(entry PRIVATE cxx_std_17)
