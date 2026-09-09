#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$PWD
export OHOS_SDK=${OHOS_SDK:-$HOME/command-line-tools/sdk/default/openharmony}
export LYCIUM_ROOT=${LYCIUM_ROOT:-$HOME/tpc_c_cplusplus-current/lycium}
export ARCH=arm64-v8a
PREFIX=$LYCIUM_ROOT/usr/aloe-mpv-direct/$ARCH
mkdir -p "$PREFIX/lib/pkgconfig" "$ROOT/build"
source "$LYCIUM_ROOT/script/envset.sh"
setarm64ENV
export PATH="$OHOS_SDK/native/build-tools/cmake/bin:$PATH"
SDK_BIN=$OHOS_SDK/native/llvm/bin
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
DEPS=(libass freetype2 fontconfig fribidi harfbuzz libpng libxml2 xz brotli bzip2 zlib_1_3_1 openssl-3.4.0 dav1d)
INCLUDES="-I$PREFIX/include"
LINKS="-L$PREFIX/lib"
for dep in "${DEPS[@]}"; do
 d="$LYCIUM_ROOT/usr/$dep/$ARCH"
 if [ -d "$d/include" ]; then INCLUDES="$INCLUDES -I$d/include"; fi
 for l in lib lib64; do
  if [ -d "$d/$l" ]; then
   LINKS="$LINKS -L$d/$l"
   PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR:$d/$l/pkgconfig"
  fi
 done
done
cat > "$PREFIX/lib/pkgconfig/zlib.pc" <<EOF
prefix=$LYCIUM_ROOT/usr/zlib_1_3_1/$ARCH
Name: zlib
Description: current tpc zlib 1.3.1
Version: 1.3.1
Libs: -L$LYCIUM_ROOT/usr/zlib_1_3_1/$ARCH/lib -lz
Cflags: -I$LYCIUM_ROOT/usr/zlib_1_3_1/$ARCH/include
EOF
export PKG_CONFIG_LIBDIR
unset PKG_CONFIG_PATH PKG_CONFIG_SYSROOT_DIR
export PREFIX SDK_BIN ROOT INCLUDES LINKS
python3 - <<'PY'
import os, shlex
from pathlib import Path
b=os.environ['SDK_BIN'];p=os.environ['PREFIX']
incs=shlex.split(os.environ['INCLUDES']);links=shlex.split(os.environ['LINKS'])
Path('cross.ini').write_text(f"""[binaries]
c = '{b}/aarch64-linux-ohos-clang'
cpp = '{b}/aarch64-linux-ohos-clang++'
ar = '{b}/llvm-ar'
strip = '{b}/llvm-strip'
pkg-config = '/usr/bin/pkg-config'
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
needs_exe_wrapper = true
[built-in options]
c_args = {incs + ['-fPIC', '-D__MUSL__=1']!r}
cpp_args = {incs + ['-fPIC', '-D__MUSL__=1']!r}
c_link_args = {links + ['-lc++', '-lnative_window', '-lnative_buffer', '-lnative_image', '-lnative_media_codecbase', '-lnative_media_vdec', '-lnative_media_core', '-lohaudio', '-lhilog_ndk.z']!r}
cpp_link_args = {links!r}
pkg_config_path = {os.environ['PKG_CONFIG_LIBDIR'].split(':')!r}
prefer_static = true
""")
PY
# Force indirect FFmpeg dependencies to resolve to private static archives.
cp "$LYCIUM_ROOT/usr/xz/$ARCH/lib/liblzma.a" "$PREFIX/lib/"
cp "$LYCIUM_ROOT/usr/zlib_1_3_1/$ARCH/lib/libz.a" "$PREFIX/lib/"
meson setup build/dav1d "$LYCIUM_ROOT/../thirdparty/dav1d/dav1d-1.5.2" --cross-file cross.ini --prefix="$PREFIX" --default-library=static --buildtype=release -Denable_tools=false -Denable_tests=false
ninja -C build/dav1d -j8
ninja -C build/dav1d install
cmake -S "$LYCIUM_ROOT/../thirdparty/libxml2/libxml2-v2.11.3" -B build/libxml2 -DCMAKE_TOOLCHAIN_FILE="$OHOS_SDK/native/build/cmake/ohos.toolchain.cmake" -DOHOS_ARCH=arm64-v8a -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF -DLIBXML2_WITH_PROGRAMS=OFF -DLIBXML2_WITH_TESTS=OFF -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_LZMA=OFF -DLIBXML2_WITH_ZLIB=OFF -DLIBXML2_WITH_HTTP=OFF -DLIBXML2_WITH_FTP=OFF
cmake --build build/libxml2 -j8
cmake --install build/libxml2
cmake -S glslang -B build/glslang -DCMAKE_TOOLCHAIN_FILE="$OHOS_SDK/native/build/cmake/ohos.toolchain.cmake" -DOHOS_ARCH=arm64-v8a -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF -DENABLE_HLSL=OFF -DENABLE_OPT=OFF -DENABLE_GLSLANG_BINARIES=OFF -DGLSLANG_TESTS=OFF -DALLOW_EXTERNAL_SPIRV_TOOLS=OFF
cmake --build build/glslang -j8
cmake --install build/glslang
if [ ! -f libplacebo/.aloe-patched ]; then
 for patch in upstream-build/patches/libplacebo/*.patch; do git -C libplacebo apply "$ROOT/$patch"; done
 touch libplacebo/.aloe-patched
fi
export PYTHONPATH="$ROOT/build/python-tools${PYTHONPATH:+:$PYTHONPATH}"
unset CFLAGS CXXFLAGS LDFLAGS
meson setup build/placebo libplacebo --cross-file cross.ini --prefix="$PREFIX" --default-library=static --buildtype=release --wrap-mode=nodownload -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false -Dd3d11=disabled -Dopengl=enabled -Dvulkan=enabled -Dglslang=enabled -Dshaderc=disabled -Dvulkan-sdk="$PREFIX" -Dprefer_static=true -Dlcms=disabled -Dlibdovi=disabled -Ddovi=enabled -Dunwind=disabled -Dvulkan-registry="$ROOT/libplacebo/3rdparty/Vulkan-Headers/registry/vk.xml"
ninja -C build/placebo -j8
ninja -C build/placebo install
mkdir -p build/ffmpeg
cd build/ffmpeg
if [ ! -f ffbuild/config.mak ]; then
 "$ROOT/ffmpeg-upstream/configure" --prefix="$PREFIX" --arch=aarch64 --cpu=armv8-a --target-os=linux --enable-cross-compile --cc="$SDK_BIN/aarch64-linux-ohos-clang" --cxx="$SDK_BIN/aarch64-linux-ohos-clang++" --ar="$SDK_BIN/llvm-ar" --ranlib="$SDK_BIN/llvm-ranlib" --strip="$SDK_BIN/llvm-strip" --pkg-config=pkg-config --pkg-config-flags=--static --extra-cflags="$INCLUDES -fPIC" --extra-ldflags="$LINKS" --enable-static --disable-shared --enable-pic --disable-doc --disable-programs --disable-debug --disable-vulkan --disable-devices --disable-avdevice --disable-muxers --disable-encoders --enable-encoder=png,mjpeg --enable-ohcodec --enable-openssl --enable-libdav1d
fi
make -j8
make install
cd "$ROOT"
if [ ! -f build/lua/liblua.a ]; then
 curl -fsSL --retry 3 https://www.lua.org/ftp/lua-5.2.4.tar.gz -o lua-5.2.4.tar.gz
 mkdir -p build/lua
 tar -xf lua-5.2.4.tar.gz --strip-components=2 -C build/lua lua-5.2.4/src
 make -C build/lua generic CC="$SDK_BIN/aarch64-linux-ohos-clang -fPIC" AR="$SDK_BIN/llvm-ar rcu" RANLIB="$SDK_BIN/llvm-ranlib" -j8
fi
cp build/lua/liblua.a "$PREFIX/lib/"
mkdir -p "$PREFIX/include/lua5.2"
cp build/lua/lua.h build/lua/luaconf.h build/lua/lualib.h build/lua/lauxlib.h "$PREFIX/include/lua5.2/"
cat > "$PREFIX/lib/pkgconfig/lua.pc" <<EOF
prefix=$PREFIX
Name: Lua
Description: Lua 5.2
Version: 5.2.4
Libs: -L$PREFIX/lib -llua -lm -ldl
Cflags: -I$PREFIX/include/lua5.2
EOF
meson setup --reconfigure --clearcache build/mpv mpv --cross-file cross.ini --prefix="$PREFIX" --default-library=shared --buildtype=release -Dprefer_static=true -Dauto_features=disabled -Dlibmpv=true -Dcplayer=false -Dtests=false -Dgpl=false -Dbuild-date=false -Dmanpage-build=disabled -Dohos=enabled -Degl-ohos=enabled -Dgl=enabled -Dvulkan=enabled -Dshaderc=disabled -Dlua=enabled -Diconv=enabled -Dzlib=enabled
ninja -C build/mpv -j8
ninja -C build/mpv install
"$SDK_BIN/llvm-readelf" -d "$PREFIX/lib/libmpv.so"
sha256sum "$PREFIX/lib/libmpv.so"
