# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(ohos)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
# 启用c++17
set(CMAKE_CXX_STANDARD 17)
if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()
# set(AKI_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../../../oh_modules/@ohos/aki) # 设置AKI根路径
# set(AKI_ENABLE_CXX_STANDARD_11 ON)
# set(CMAKE_MODULE_PATH ${AKI_ROOT_PATH})
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
add_library(entry SHARED napi_init.cpp )
target_link_libraries(entry PUBLIC libace_napi.z.so avcodec avformat avutil libhilog_ndk.z.so )
target_compile_features(entry PRIVATE cxx_std_17)
