#!/bin/bash
# build-all.sh - Cross compile MLT for Windows from Alpine WSL
# Usage: ./build-all.sh

set -e

PREFIX="$HOME/tools/win-deps"
SRC="$HOME/tools/src"
CROSS="x86_64-w64-mingw32"
CROSS_FILE="$HOME/tools/mingw-cross.ini"
JOBS=$(nproc)

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"

mkdir -p "$SRC" "$PREFIX"

# ─── Meson cross file ───────────────────────────────────────────────────────
setup_crossfile() {
  cat > "$CROSS_FILE" << EOF
[binaries]
c = '$CROSS-gcc'
cpp = '$CROSS-g++'
ar = '$CROSS-ar'
strip = '$CROSS-strip'
windres = '$CROSS-windres'
pkgconfig = 'pkg-config'

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[properties]
pkg_config_libdir = '$PREFIX/lib/pkgconfig'
EOF
  echo "[OK] Cross file: $CROSS_FILE"
}

# ─── cmake helper ───────────────────────────────────────────────────────────
cmake_build() {
  local dir="$1"; shift
  mkdir -p "$dir/build" && cd "$dir/build"

  cmake .. \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_CROSSCOMPILING=ON \
    -DCMAKE_C_COMPILER=$CROSS-gcc \
    -DCMAKE_CXX_COMPILER=$CROSS-g++ \
    -DCMAKE_RC_COMPILER=$CROSS-windres \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DPKG_CONFIG_EXECUTABLE=$(which pkg-config) \
    -DCMAKE_FIND_ROOT_PATH="$PREFIX" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_USE_WIN32_THREADS_INIT=ON \
    -DTHREADS_PREFER_PTHREAD_FLAG=OFF \
    -DTHREADS_HAVE_PTHREAD_ARG=OFF \
    -DCMAKE_HAVE_THREADS_LIBRARY=ON \
    -DCMAKE_C_FLAGS="-I$PREFIX/include" \
    -DCMAKE_CXX_FLAGS="-I$PREFIX/include" \
    -DCMAKE_EXE_LINKER_FLAGS="-L$PREFIX/lib" \
    -DCMAKE_SHARED_LINKER_FLAGS="-L$PREFIX/lib" \
    "$@"

  make -j$JOBS && make install
  cd "$SRC"
}

# ─── autoconf helper ────────────────────────────────────────────────────────
autoconf_build() {
  local dir="$1"; shift
  cd "$dir"
  ./configure \
    --host=$CROSS \
    --prefix="$PREFIX" \
    --enable-shared \
    --disable-static \
    "$@"
  make -j$JOBS && make install
  cd "$SRC"
}

# ─── 1. zlib ────────────────────────────────────────────────────────────────
build_zlib() {
  echo ">>> Building zlib..."
  cd "$SRC"
  wget -q https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
  tar -xzf zlib-1.3.1.tar.gz
  cmake_build zlib-1.3.1
  echo "[OK] zlib"
}

# ─── 2. libiconv ────────────────────────────────────────────────────────────
build_libiconv() {
  echo ">>> Building libiconv..."
  cd "$SRC"
  wget -q https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz
  tar -xzf libiconv-1.17.tar.gz
  autoconf_build libiconv-1.17
  echo "[OK] libiconv"
}

# ─── 3. xz/liblzma ──────────────────────────────────────────────────────────
build_xz() {
  echo ">>> Building xz/liblzma..."
  cd "$SRC"
  wget -q https://github.com/tukaani-project/xz/releases/download/v5.4.6/xz-5.4.6.tar.gz
  tar -xzf xz-5.4.6.tar.gz
  autoconf_build xz-5.4.6
  echo "[OK] xz"
}

# ─── 4. libxml2 ─────────────────────────────────────────────────────────────
build_libxml2() {
  echo ">>> Building libxml2..."
  cd "$SRC"
  wget -q https://download.gnome.org/sources/libxml2/2.12/libxml2-2.12.0.tar.xz
  tar -xf libxml2-2.12.0.tar.xz
  cmake_build libxml2-2.12.0 \
    -DLIBXML2_WITH_ICONV=ON \
    -DLIBXML2_WITH_ZLIB=ON \
    -DLIBXML2_WITH_LZMA=ON \
    -DLIBXML2_WITH_PYTHON=OFF \
    -DLIBXML2_WITH_MODULES=OFF \
    -DLIBXML2_WITH_PROGRAMS=OFF \
    -DLIBXML2_TESTS=OFF
  echo "[OK] libxml2"
}

# ─── 5. glib ────────────────────────────────────────────────────────────────
build_glib() {
  echo ">>> Building glib..."
  cd "$SRC"
  wget -q https://download.gnome.org/sources/glib/2.78/glib-2.78.0.tar.xz
  tar -xf glib-2.78.0.tar.xz
  mkdir -p glib-2.78.0/build && cd glib-2.78.0/build
  meson setup .. --prefix="$PREFIX" --cross-file "$CROSS_FILE"
  ninja -j$JOBS && ninja install
  cd "$SRC"
  echo "[OK] glib"
}

# ─── 6. freetype ────────────────────────────────────────────────────────────
build_freetype() {
  echo ">>> Building freetype..."
  cd "$SRC"
  wget -q https://download.savannah.gnu.org/releases/freetype/freetype-2.13.2.tar.gz
  tar -xzf freetype-2.13.2.tar.gz
  cmake_build freetype-2.13.2
  echo "[OK] freetype"
}

# ─── 7. expat ───────────────────────────────────────────────────────────────
build_expat() {
  echo ">>> Building expat..."
  cd "$SRC"
  wget -q https://github.com/libexpat/libexpat/releases/download/R_2_5_0/expat-2.5.0.tar.gz
  tar -xzf expat-2.5.0.tar.gz
  autoconf_build expat-2.5.0
  echo "[OK] expat"
}

# ─── 8. fontconfig ──────────────────────────────────────────────────────────
build_fontconfig() {
  echo ">>> Building fontconfig..."
  cd "$SRC"
  wget -q https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.15.0.tar.gz
  tar -xzf fontconfig-2.15.0.tar.gz
  cd fontconfig-2.15.0
  ./configure \
    --host=$CROSS \
    --prefix="$PREFIX" \
    --enable-shared \
    --disable-static \
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
  make -j$JOBS
  make install-data install-exec  # skip fc-cache (tidak bisa run di Linux)
  cd "$SRC"
  echo "[OK] fontconfig"
}

# ─── 9. harfbuzz ────────────────────────────────────────────────────────────
build_harfbuzz() {
  echo ">>> Building harfbuzz..."
  cd "$SRC"
  wget -q https://github.com/harfbuzz/harfbuzz/releases/download/8.3.0/harfbuzz-8.3.0.tar.xz
  tar -xf harfbuzz-8.3.0.tar.xz
  mkdir -p harfbuzz-8.3.0/build && cd harfbuzz-8.3.0/build
  meson setup .. \
    --prefix="$PREFIX" \
    --cross-file "$CROSS_FILE" \
    -Dtests=disabled -Ddocs=disabled
  ninja -j$JOBS && ninja install
  cd "$SRC"
  echo "[OK] harfbuzz"
}

# ─── 10. pango ──────────────────────────────────────────────────────────────
build_pango() {
  echo ">>> Building pango..."
  cd "$SRC"
  wget -q https://download.gnome.org/sources/pango/1.51/pango-1.51.0.tar.xz
  tar -xf pango-1.51.0.tar.xz
  mkdir -p pango-1.51.0/build && cd pango-1.51.0/build
  meson setup .. \
    --prefix="$PREFIX" \
    --cross-file "$CROSS_FILE" \
    -Dcairo=disabled
  ninja -j$JOBS && ninja install
  cd "$SRC"
  echo "[OK] pango"
}

# ─── 11. libsamplerate ──────────────────────────────────────────────────────
build_libsamplerate() {
  echo ">>> Building libsamplerate..."
  cd "$SRC"
  wget -q https://github.com/libsndfile/libsamplerate/archive/refs/tags/0.2.2.tar.gz \
    -O libsamplerate-0.2.2.tar.gz
  tar -xzf libsamplerate-0.2.2.tar.gz
  cmake_build libsamplerate-0.2.2 \
    -DLIBSAMPLERATE_EXAMPLES=OFF \
    -DLIBSAMPLERATE_TESTS=OFF
  echo "[OK] libsamplerate"
}

# ─── 12. rubberband ─────────────────────────────────────────────────────────
# build_rubberband() {
#   echo ">>> Building rubberband..."
#   cd "$SRC"
#   wget -q https://breakfastquay.com/files/releases/rubberband-3.3.0.tar.bz2
#   tar -xjf rubberband-3.3.0.tar.bz2
#   mkdir -p rubberband-3.3.0/build && cd rubberband-3.3.0/build
#   meson setup .. \
#     --prefix="$PREFIX" \
#     --cross-file "$CROSS_FILE" \
#     -Dfft=builtin -Dresampler=builtin
#   ninja -j$JOBS && ninja install
#   cd "$SRC"
#   echo "[OK] rubberband"
# }

build_rubberband() {
  echo ">>> Building rubberband..."

  cd "$SRC"
  rm -rf rubberband-3.3.0
  wget -q https://breakfastquay.com/files/releases/rubberband-3.3.0.tar.bz2
  tar -xjf rubberband-3.3.0.tar.bz2

  cd rubberband-3.3.0
  rm -rf build

  meson setup build \
    --prefix="$PREFIX" \
    --cross-file "$CROSS_FILE" \
    -Dfft=builtin \
    -Dresampler=builtin \
    -Ddefault_library=static \
    -Djni=disabled \
    -Dladspa=disabled \
    -Dlv2=disabled \
    -Dvamp=disabled

  ninja -C build -j$JOBS || exit 1
  ninja -C build install || exit 1

  # 🔍 VALIDASI (penting)
  if [ ! -f "$PREFIX/lib/pkgconfig/rubberband.pc" ]; then
    echo "❌ rubberband.pc not found!"
    exit 1
  fi

  cd "$SRC"
  echo "[OK] rubberband"
}

# ─── 13. x264 ───────────────────────────────────────────────────────────────
build_x264() {
  echo ">>> Building x264..."
  cd "$SRC"
  wget -q https://code.videolan.org/videolan/x264/-/archive/master/x264-master.tar.gz
  tar -xzf x264-master.tar.gz && cd x264-master
  ./configure \
    --host=$CROSS \
    --prefix="$PREFIX" \
    --enable-shared --disable-static --disable-cli \
    --cross-prefix=$CROSS-
  make -j$JOBS && make install
  cd "$SRC"
  echo "[OK] x264"
}

# ─── 14. FFmpeg ─────────────────────────────────────────────────────────────
build_ffmpeg() {
  echo ">>> Building FFmpeg..."
  cd "$SRC"
  wget -q https://ffmpeg.org/releases/ffmpeg-7.1.tar.gz
  tar -xzf ffmpeg-7.1.tar.gz && cd ffmpeg-7.1
  PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
  PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" \
  ./configure \
    --cross-prefix=$CROSS- \
    --arch=x86_64 \
    --target-os=mingw32 \
    --prefix="$PREFIX" \
    --enable-shared --disable-static \
    --enable-gpl --enable-libx264 \
    --pkg-config=pkg-config \
    --pkg-config-flags="--define-prefix" \
    --extra-cflags="-I$PREFIX/include" \
    --extra-ldflags="-L$PREFIX/lib" \
    --extra-libs="-lx264"
  make -j$JOBS && make install
  cd "$SRC"
  echo "[OK] FFmpeg"
}

# ─── 15. SDL2 ───────────────────────────────────────────────────────────────
build_sdl2() {
  echo ">>> Building SDL2..."
  cd "$SRC"
  wget -q https://github.com/libsdl-org/SDL/releases/download/release-2.30.0/SDL2-2.30.0.tar.gz
  tar -xzf SDL2-2.30.0.tar.gz
  cmake_build SDL2-2.30.0
  echo "[OK] SDL2"
}

# ─── 16. libexif ────────────────────────────────────────────────────────────
build_libexif() {
  echo ">>> Building libexif..."
  cd "$SRC"
  wget -q https://github.com/libexif/libexif/releases/download/v0.6.25/libexif-0.6.25.tar.xz
  tar -xf libexif-0.6.25.tar.xz
  autoconf_build libexif-0.6.25
  echo "[OK] libexif"
}

# ─── 17. libebur128 ─────────────────────────────────────────────────────────
build_libebur128() {
  echo ">>> Building libebur128..."
  cd "$SRC"
  git clone https://github.com/jiixyj/libebur128.git
  cmake_build libebur128
  echo "[OK] libebur128"
}

# ─── 18. dlfcn-win32 ────────────────────────────────────────────────────────
build_dlfcn() {
  echo ">>> Building dlfcn-win32..."
  cd "$SRC"
  git clone https://github.com/dlfcn-win32/dlfcn-win32.git
  cmake_build dlfcn-win32
  echo "[OK] dlfcn-win32"
}

# ─── 19. MLT ────────────────────────────────────────────────────────────────
# build_mlt() {
#   echo ">>> Building MLT..."
#   cd "$SRC"
#   git clone https://github.com/mltframework/mlt.git mlt-win
#   cd mlt-win
#   mkdir -p build && cd build
#   cmake .. \
#     -DCMAKE_SYSTEM_NAME=Windows \
#     -DCMAKE_C_COMPILER=$CROSS-gcc \
#     -DCMAKE_CXX_COMPILER=$CROSS-g++ \
#     -DCMAKE_INSTALL_PREFIX="$PREFIX" \
#     -DCMAKE_PREFIX_PATH="$PREFIX" \
#     -DCMAKE_BUILD_TYPE=Release \
#     -DCMAKE_EXE_LINKER_FLAGS="-L$PREFIX/lib" \
#     -DCMAKE_SHARED_LINKER_FLAGS="-L$PREFIX/lib" \
#     -DCMAKE_C_FLAGS="-I$PREFIX/include" \
#     -DCMAKE_CXX_FLAGS="-I$PREFIX/include" \
#     -DMOD_QT6=OFF \
#     -DMOD_MOVIT=OFF \
#     -DMOD_FREI0R=OFF \
#     -DMOD_GDK=OFF \
#     -DMOD_JACKRACK=OFF \
#     -DMOD_SOX=OFF \
#     -DMOD_VIDSTAB=OFF \
#     -DMOD_VORBIS=OFF \
#     -DMOD_RTAUDIO=OFF \
#     -DMOD_SWIG=OFF \
#     -DENABLE_CLANG_FORMAT=OFF
#   make -j$JOBS && make install
#   cd "$SRC"
#   echo "[OK] MLT"
# }

build_mlt() {
  echo ">>> Building MLT..."

  cd "$SRC"
  rm -rf mlt-win
  git clone https://github.com/mltframework/mlt.git mlt-win
  cd mlt-win

  mkdir -p build && cd build

  cmake .. \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_CROSSCOMPILING=ON \
    -DCMAKE_C_COMPILER=$CROSS-gcc \
    -DCMAKE_CXX_COMPILER=$CROSS-g++ \
    -DCMAKE_RC_COMPILER=$CROSS-windres \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_FIND_ROOT_PATH="$PREFIX" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DMOD_QT6=OFF \
    -DMOD_MOVIT=OFF \
    -DMOD_FREI0R=OFF \
    -DMOD_GDK=OFF \
    -DMOD_JACKRACK=OFF \
    -DMOD_SOX=OFF \
    -DMOD_VIDSTAB=OFF \
    -DMOD_VORBIS=OFF \
    -DMOD_RTAUDIO=OFF \
    -DMOD_SWIG=OFF \
    -DENABLE_CLANG_FORMAT=OFF

  make -j$JOBS || exit 1
  make install || exit 1

  # VALIDASI
  if [ ! -f "$PREFIX/bin/melt.exe" ]; then
    echo "❌ melt.exe NOT FOUND"
    find "$PREFIX" -name "*melt*" || true
    exit 1
  fi

  echo "[OK] MLT"
}


# ─── MAIN ───────────────────────────────────────────────────────────────────
echo "================================================"
echo " MLT Windows Cross Compile - Alpine WSL"
echo "================================================"

setup_crossfile

build_zlib
build_libiconv
build_xz
build_libxml2
build_glib
build_freetype
build_expat
build_fontconfig
build_harfbuzz
build_pango
build_libsamplerate
build_rubberband
build_x264
build_ffmpeg
build_sdl2
build_libexif
build_libebur128
build_dlfcn
build_mlt

echo ""
echo "================================================"
echo " DONE! Output: $PREFIX/melt.exe"
echo "================================================"
