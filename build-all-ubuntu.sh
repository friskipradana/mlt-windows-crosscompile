#!/bin/bash
# build-all-ubuntu.sh - Cross compile MLT for Windows from Ubuntu (GitHub Actions)
# Merged & fixed from working Alpine WSL version
# Usage: ./build-all-ubuntu.sh

set -e

PREFIX="$HOME/tools/win-deps"
SRC="$HOME/tools/src"
CROSS="x86_64-w64-mingw32"
CROSS_FILE="$HOME/tools/mingw-cross.ini"
# GitHub Actions biasanya 2-4 core
JOBS=$(( $(nproc) > 2 ? $(nproc) - 1 : 2 ))

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$PREFIX"

# Propagate flags ke semua build
# export CFLAGS="-I$PREFIX/include"
# export CXXFLAGS="-I$PREFIX/include"
# export LDFLAGS="-L$PREFIX/lib"
export CFLAGS="-I$PREFIX/include -pthread"
export CXXFLAGS="-I$PREFIX/include -pthread"
export LDFLAGS="-L$PREFIX/lib -lwinpthread"

mkdir -p "$SRC" "$PREFIX/lib" "$PREFIX/bin" "$PREFIX/include"

# ─── Helper: skip kalau sudah di-download ───────────────────────────────────
download_if_missing() {
  local url="$1"
  local filename="$2"
  if [ ! -f "$SRC/$filename" ]; then
    wget -q "$url" -O "$SRC/$filename"
  else
    echo "  [skip download] $filename"
  fi
}

# ─── Meson cross file ───────────────────────────────────────────────────────
# FIX: c_args/cpp_args pindah ke [built-in options] (deprecated di [properties] sejak meson 1.2+)
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
needs_exe_wrapper = true

[built-in options]
c_args = ['-I$PREFIX/include']
c_link_args = ['-L$PREFIX/lib']
cpp_args = ['-I$PREFIX/include']
cpp_link_args = ['-L$PREFIX/lib']
EOF

  echo "[OK] Cross file: $CROSS_FILE"
}

setup_pthread_lib() {
  echo ">>> Copying pthread libs..."

  SYSROOT_LIB="/usr/x86_64-w64-mingw32/lib"

  for f in libpthread.a libpthread.dll.a libwinpthread.a libwinpthread.dll.a; do
    if [ -f "$SYSROOT_LIB/$f" ]; then
      cp "$SYSROOT_LIB/$f" "$PREFIX/lib/"
      echo "  [copied] $f"
    fi
  done

  # symlink fallback
  if [ ! -f "$PREFIX/lib/libpthread.dll.a" ] && [ -f "$PREFIX/lib/libwinpthread.dll.a" ]; then
    ln -sf "$PREFIX/lib/libwinpthread.dll.a" "$PREFIX/lib/libpthread.dll.a"
    echo "  [symlink] libpthread.dll.a -> libwinpthread.dll.a"
  fi
}

setup_pthread_dll() {
  echo ">>> Copying winpthread runtime DLL..."

  # FIX: di Ubuntu DLL tidak di /usr/x86_64-w64-mingw32/bin, cari di semua lokasi
  PTHREAD_DLL=$(find /usr -name "libwinpthread-1.dll" 2>/dev/null | head -1)

  if [ -n "$PTHREAD_DLL" ]; then
    cp "$PTHREAD_DLL" "$PREFIX/bin/"
    echo "  [copied] libwinpthread-1.dll dari $PTHREAD_DLL"
  else
    echo "  [WARN] libwinpthread-1.dll tidak ditemukan, coba install ulang..."
    sudo apt-get install -y -q mingw-w64 2>/dev/null || true
    PTHREAD_DLL=$(find /usr -name "libwinpthread-1.dll" 2>/dev/null | head -1)
    if [ -n "$PTHREAD_DLL" ]; then
      cp "$PTHREAD_DLL" "$PREFIX/bin/"
      echo "  [copied] libwinpthread-1.dll dari $PTHREAD_DLL"
    else
      echo "  [ERROR] libwinpthread-1.dll benar-benar tidak ditemukan!"
      echo "  Debug: find /usr -name 'libwinpthread*'"
      find /usr -name "libwinpthread*" 2>/dev/null || true
    fi
  fi
}

setup_cross_env() {
  setup_crossfile
  setup_pthread_lib
  setup_pthread_dll
}

# ─── cmake helper ───────────────────────────────────────────────────────────
cmake_build() {
  local dir="$1"; shift
  # Skip kalau sudah berhasil di-build
  if [ -f "$SRC/$dir/.build_done" ]; then
    echo "  [skip] $dir"
    return 0
  fi
  mkdir -p "$SRC/$dir/build" && cd "$SRC/$dir/build"
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
    -DCMAKE_C_FLAGS="-I$PREFIX/include" \
    -DCMAKE_CXX_FLAGS="-I$PREFIX/include" \
    -DCMAKE_EXE_LINKER_FLAGS="-L$PREFIX/lib" \
    -DCMAKE_SHARED_LINKER_FLAGS="-L$PREFIX/lib" \
    "$@"
  make -j$JOBS && make install
  touch "$SRC/$dir/.build_done"
  cd "$SRC"
}

# ─── autoconf helper ────────────────────────────────────────────────────────
autoconf_build() {
  local dir="$1"; shift
  if [ -f "$SRC/$dir/.build_done" ]; then
    echo "  [skip] $dir"
    return 0
  fi
  cd "$SRC/$dir"
  ./configure \
    --host=$CROSS \
    --prefix="$PREFIX" \
    --enable-shared \
    --disable-static \
    CFLAGS="-I$PREFIX/include" \
    LDFLAGS="-L$PREFIX/lib" \
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
    "$@"
  make -j$JOBS && make install
  touch ".build_done"
  cd "$SRC"
}

# ─── meson helper ───────────────────────────────────────────────────────────
meson_build() {
  local dir="$1"; shift
  if [ -f "$SRC/$dir/.build_done" ]; then
    echo "  [skip] $dir"
    return 0
  fi
  mkdir -p "$SRC/$dir/build" && cd "$SRC/$dir/build"
  meson setup .. \
    --prefix="$PREFIX" \
    --cross-file "$CROSS_FILE" \
    --default-library=shared \
    --pkg-config-path="$PREFIX/lib/pkgconfig" \
    "$@"
  ninja -j$JOBS && ninja install
  touch "$SRC/$dir/.build_done"
  cd "$SRC"
}

# ─── 1. zlib ────────────────────────────────────────────────────────────────
build_zlib() {
  echo ">>> Building zlib..."
  cd "$SRC"
  download_if_missing \
    https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz \
    zlib-1.3.1.tar.gz
  [ -d zlib-1.3.1 ] || tar -xzf zlib-1.3.1.tar.gz
  cmake_build zlib-1.3.1
  echo "[OK] zlib"
}

# ─── 2. libiconv ────────────────────────────────────────────────────────────
build_libiconv() {
  echo ">>> Building libiconv..."
  cd "$SRC"
  download_if_missing \
    https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz \
    libiconv-1.17.tar.gz
  [ -d libiconv-1.17 ] || tar -xzf libiconv-1.17.tar.gz
  autoconf_build libiconv-1.17
  echo "[OK] libiconv"
}

# ─── 3. xz/liblzma ──────────────────────────────────────────────────────────
build_xz() {
  echo ">>> Building xz/liblzma..."
  cd "$SRC"
  download_if_missing \
    https://github.com/tukaani-project/xz/releases/download/v5.4.6/xz-5.4.6.tar.gz \
    xz-5.4.6.tar.gz
  [ -d xz-5.4.6 ] || tar -xzf xz-5.4.6.tar.gz
  autoconf_build xz-5.4.6
  echo "[OK] xz"
}

# ─── 4. libxml2 ─────────────────────────────────────────────────────────────
build_libxml2() {
  echo ">>> Building libxml2..."
  cd "$SRC"
  download_if_missing \
    https://download.gnome.org/sources/libxml2/2.12/libxml2-2.12.0.tar.xz \
    libxml2-2.12.0.tar.xz
  [ -d libxml2-2.12.0 ] || tar -xf libxml2-2.12.0.tar.xz
  cmake_build libxml2-2.12.0 \
    -DLIBXML2_WITH_ICONV=ON \
    -DLIBXML2_WITH_ZLIB=ON \
    -DLIBXML2_WITH_LZMA=ON \
    -DLIBXML2_WITH_PYTHON=OFF \
    -DLIBXML2_WITH_MODULES=OFF \
    -DLIBXML2_WITH_PROGRAMS=OFF
  echo "[OK] libxml2"
}

# ─── 5. pcre2 (wajib untuk glib 2.74+) ─────────────────────────────────────
# FIX: glib 2.74+ hapus opsi -Dpcre2, pcre2 jadi mandatory dependency.
# Di Alpine pcre2 tersedia lewat system, di Ubuntu harus cross-compile sendiri.
build_pcre2() {
  echo ">>> Building pcre2..."
  cd "$SRC"
  download_if_missing \
    https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.42/pcre2-10.42.tar.gz \
    pcre2-10.42.tar.gz
  [ -d pcre2-10.42 ] || tar -xzf pcre2-10.42.tar.gz
  cmake_build pcre2-10.42 \
    -DPCRE2_BUILD_PCRE2_8=ON \
    -DPCRE2_BUILD_PCRE2_16=ON \
    -DPCRE2_BUILD_PCRE2_32=ON \
    -DPCRE2_SUPPORT_UNICODE=ON \
    -DPCRE2_BUILD_TESTS=OFF \
    -DPCRE2_BUILD_PCRE2GREP=OFF
  echo "[OK] pcre2"
}

# ─── 6. glib ────────────────────────────────────────────────────────────────
build_glib() {
  echo ">>> Building glib..."
  cd "$SRC"
  download_if_missing \
    https://download.gnome.org/sources/glib/2.78/glib-2.78.0.tar.xz \
    glib-2.78.0.tar.xz
  [ -d glib-2.78.0 ] || tar -xf glib-2.78.0.tar.xz
  # FIX: tidak ada opsi -Dpcre2 di glib 2.74+ (dihapus, jadi mandatory)
  # FIX: tidak ada opsi -Dglib_assert / -Dglib_checks di versi ini
  # Sama persis dengan Alpine yang bekerja
  meson_build glib-2.78.0 \
    --wrap-mode=default \
    -Dtests=false \
    -Dinstalled_tests=false \
    -Dlibmount=disabled \
    -Dforce_posix_threads=true
  echo "[OK] glib"
}

# ─── 7. freetype ────────────────────────────────────────────────────────────
build_freetype() {
  echo ">>> Building freetype..."
  cd "$SRC"
  download_if_missing \
    https://download.savannah.gnu.org/releases/freetype/freetype-2.13.2.tar.gz \
    freetype-2.13.2.tar.gz
  [ -d freetype-2.13.2 ] || tar -xzf freetype-2.13.2.tar.gz
  # Disable harfbuzz dulu, akan di-rebuild setelah harfbuzz selesai (opsional)
  cmake_build freetype-2.13.2 \
    -DFT_DISABLE_HARFBUZZ=ON \
    -DFT_DISABLE_BZIP2=ON
  echo "[OK] freetype"
}

# ─── 8. expat ───────────────────────────────────────────────────────────────
build_expat() {
  echo ">>> Building expat..."
  cd "$SRC"
  download_if_missing \
    https://github.com/libexpat/libexpat/releases/download/R_2_5_0/expat-2.5.0.tar.gz \
    expat-2.5.0.tar.gz
  [ -d expat-2.5.0 ] || tar -xzf expat-2.5.0.tar.gz
  autoconf_build expat-2.5.0
  echo "[OK] expat"
}

# ─── 9. fontconfig ──────────────────────────────────────────────────────────
build_fontconfig() {
  echo ">>> Building fontconfig..."
  cd "$SRC"
  download_if_missing \
    https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.15.0.tar.gz \
    fontconfig-2.15.0.tar.gz
  [ -d fontconfig-2.15.0 ] || tar -xzf fontconfig-2.15.0.tar.gz

  if [ -f "$SRC/fontconfig-2.15.0/.build_done" ]; then
    echo "  [skip] fontconfig"
  else
    cd "$SRC/fontconfig-2.15.0"
    ./configure \
      --host=$CROSS \
      --prefix="$PREFIX" \
      --enable-shared \
      --disable-static \
      CFLAGS="-I$PREFIX/include" \
      LDFLAGS="-L$PREFIX/lib" \
      PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
    make -j$JOBS
    make install-exec
    make install-data || true  # skip fc-cache, tidak bisa run di Linux
    touch ".build_done"
    cd "$SRC"
  fi
  echo "[OK] fontconfig"
}

# ─── 10. harfbuzz ────────────────────────────────────────────────────────────
build_harfbuzz() {
  echo ">>> Building harfbuzz..."
  cd "$SRC"
  download_if_missing \
    https://github.com/harfbuzz/harfbuzz/releases/download/8.3.0/harfbuzz-8.3.0.tar.xz \
    harfbuzz-8.3.0.tar.xz
  [ -d harfbuzz-8.3.0 ] || tar -xf harfbuzz-8.3.0.tar.xz
  meson_build harfbuzz-8.3.0 \
    -Dtests=disabled \
    -Ddocs=disabled \
    -Dbenchmark=disabled
  echo "[OK] harfbuzz"
}

# ─── 11. pango ──────────────────────────────────────────────────────────────
build_pango() {
  echo ">>> Building pango..."
  cd "$SRC"
  download_if_missing \
    https://download.gnome.org/sources/pango/1.51/pango-1.51.0.tar.xz \
    pango-1.51.0.tar.xz
  [ -d pango-1.51.0 ] || tar -xf pango-1.51.0.tar.xz
  meson_build pango-1.51.0 \
    -Dcairo=disabled \
    -Dgtk_doc=false \
    -Dintrospection=disabled
  echo "[OK] pango"
}

# ─── 12. libsamplerate ──────────────────────────────────────────────────────
build_libsamplerate() {
  echo ">>> Building libsamplerate..."
  cd "$SRC"
  download_if_missing \
    https://github.com/libsndfile/libsamplerate/archive/refs/tags/0.2.2.tar.gz \
    libsamplerate-0.2.2.tar.gz
  [ -d libsamplerate-0.2.2 ] || tar -xzf libsamplerate-0.2.2.tar.gz
  cmake_build libsamplerate-0.2.2 \
    -DLIBSAMPLERATE_EXAMPLES=OFF \
    -DLIBSAMPLERATE_TESTS=OFF
  echo "[OK] libsamplerate"
}

# ─── 13. rubberband ─────────────────────────────────────────────────────────
build_rubberband() {
  echo ">>> Building rubberband..."
  cd "$SRC"
  download_if_missing \
    https://breakfastquay.com/files/releases/rubberband-3.3.0.tar.bz2 \
    rubberband-3.3.0.tar.bz2
  [ -d rubberband-3.3.0 ] || tar -xjf rubberband-3.3.0.tar.bz2

  if [ -f "$SRC/rubberband-3.3.0/.build_done" ]; then
    echo "  [skip] rubberband"
  else
    mkdir -p "$SRC/rubberband-3.3.0/build" && cd "$SRC/rubberband-3.3.0/build"
    meson setup .. \
      --prefix="$PREFIX" \
      --cross-file "$CROSS_FILE" \
      --default-library=static \
      --wrap-mode=nodownload \
      -Dfft=builtin \
      -Dresampler=builtin \
      -Djni=disabled \
      -Dladspa=disabled \
      -Dlv2=disabled \
      -Dvamp=disabled
    ninja -j$JOBS && ninja install
    touch "$SRC/rubberband-3.3.0/.build_done"
    cd "$SRC"
  fi

  [ -f "$PREFIX/lib/pkgconfig/rubberband.pc" ] || \
    { echo "❌ rubberband.pc not found!"; exit 1; }
  echo "[OK] rubberband"
}

# ─── 14. x264 ───────────────────────────────────────────────────────────────
build_x264() {
  echo ">>> Building x264..."
  cd "$SRC"
  download_if_missing \
    https://code.videolan.org/videolan/x264/-/archive/master/x264-master.tar.gz \
    x264-master.tar.gz
  [ -d x264-master ] || tar -xzf x264-master.tar.gz

  if [ -f "$SRC/x264-master/.build_done" ]; then
    echo "  [skip] x264"
  else
    cd "$SRC/x264-master"
    ./configure \
      --host=$CROSS \
      --prefix="$PREFIX" \
      --enable-shared \
      --disable-static \
      --disable-cli \
      --cross-prefix=$CROSS-
    make -j$JOBS && make install
    touch ".build_done"
    cd "$SRC"
  fi
  echo "[OK] x264"
}

# ─── 15. FFmpeg ─────────────────────────────────────────────────────────────
build_ffmpeg() {
  echo ">>> Building FFmpeg..."
  cd "$SRC"
  download_if_missing \
    https://ffmpeg.org/releases/ffmpeg-7.1.tar.gz \
    ffmpeg-7.1.tar.gz
  [ -d ffmpeg-7.1 ] || tar -xzf ffmpeg-7.1.tar.gz

  if [ -f "$SRC/ffmpeg-7.1/.build_done" ]; then
    echo "  [skip] FFmpeg"
  else
    cd "$SRC/ffmpeg-7.1"
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
    PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" \
    ./configure \
      --cross-prefix=$CROSS- \
      --arch=x86_64 \
      --target-os=mingw32 \
      --prefix="$PREFIX" \
      --enable-shared \
      --disable-static \
      --enable-gpl \
      --enable-libx264 \
      --pkg-config=pkg-config \
      --pkg-config-flags="--define-prefix" \
      --extra-cflags="-I$PREFIX/include" \
      --extra-ldflags="-L$PREFIX/lib" \
      --extra-libs="-lx264"
    make -j$JOBS && make install
    touch ".build_done"
    cd "$SRC"
  fi
  echo "[OK] FFmpeg"
}

# ─── 16. SDL2 ───────────────────────────────────────────────────────────────
build_sdl2() {
  echo ">>> Building SDL2..."
  cd "$SRC"
  download_if_missing \
    https://github.com/libsdl-org/SDL/releases/download/release-2.30.0/SDL2-2.30.0.tar.gz \
    SDL2-2.30.0.tar.gz
  [ -d SDL2-2.30.0 ] || tar -xzf SDL2-2.30.0.tar.gz
  cmake_build SDL2-2.30.0
  echo "[OK] SDL2"
}

# ─── 17. libexif ────────────────────────────────────────────────────────────
build_libexif() {
  echo ">>> Building libexif..."
  cd "$SRC"
  download_if_missing \
    https://github.com/libexif/libexif/releases/download/v0.6.25/libexif-0.6.25.tar.xz \
    libexif-0.6.25.tar.xz
  [ -d libexif-0.6.25 ] || tar -xf libexif-0.6.25.tar.xz
  autoconf_build libexif-0.6.25
  echo "[OK] libexif"
}

# ─── 18. libebur128 ─────────────────────────────────────────────────────────
build_libebur128() {
  echo ">>> Building libebur128..."
  cd "$SRC"
  [ -d libebur128 ] || git clone --depth=1 https://github.com/jiixyj/libebur128.git
  cmake_build libebur128
  echo "[OK] libebur128"
}

# ─── 19. dlfcn-win32 ────────────────────────────────────────────────────────
build_dlfcn() {
  echo ">>> Building dlfcn-win32..."
  cd "$SRC"
  [ -d dlfcn-win32 ] || git clone --depth=1 https://github.com/dlfcn-win32/dlfcn-win32.git
  cmake_build dlfcn-win32
  echo "[OK] dlfcn-win32"
}

# ─── 20. MLT ────────────────────────────────────────────────────────────────
build_mlt() {
  echo ">>> Building MLT..."
  cd "$SRC"
  [ -d mlt-win ] || git clone --depth=1 https://github.com/mltframework/mlt.git mlt-win
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
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_C_FLAGS="-I$PREFIX/include -pthread" \
    -DCMAKE_CXX_FLAGS="-I$PREFIX/include -pthread" \
    -DCMAKE_EXE_LINKER_FLAGS="-L$PREFIX/lib -lwinpthread" \
    -DCMAKE_SHARED_LINKER_FLAGS="-L$PREFIX/lib -lwinpthread" \
    -DCMAKE_THREAD_LIBS_INIT="-lwinpthread" \
    -DCMAKE_HAVE_THREADS_LIBRARY=ON \
    -DCMAKE_USE_WIN32_THREADS_INIT=OFF \
    -DCMAKE_USE_PTHREADS_INIT=ON \
    -DTHREADS_PREFER_PTHREAD_FLAG=ON \
    -DMLT_BUILD_APP=ON \
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
    -DMOD_DECKLINK=OFF \
    -DENABLE_CLANG_FORMAT=OFF

  make -j$JOBS && make install

  # fallback: copy melt.exe dari build dir
  MELT_PATH=$(find . -name "melt.exe" 2>/dev/null | head -1)
  if [ -n "$MELT_PATH" ]; then
    echo "  [found] melt.exe di build: $MELT_PATH"
    mkdir -p "$PREFIX/bin"
    cp -f "$MELT_PATH" "$PREFIX/bin/"
  fi

  # fallback: copy libmlt*.dll dari build dir
  echo "  [fallback] copying libmlt DLLs..."
  find "$SRC/mlt-win/build" -name "libmlt*.dll" | while read dll; do
    cp "$dll" "$PREFIX/bin/"
    echo "  [copied] $(basename $dll)"
  done

  # fallback: copy modules dari build dir ke lib/mlt-7
  echo "  [fallback] copying MLT modules..."
  mkdir -p "$PREFIX/lib/mlt-7"
  find "$SRC/mlt-win/build/src/modules" -name "*.dll" | while read dll; do
    cp "$dll" "$PREFIX/lib/mlt-7/"
    echo "  [copied] $(basename $dll)"
  done

  # fallback: copy share/mlt-7 dari source tree
  echo "  [fallback] copying MLT share data..."
  mkdir -p "$PREFIX/share/mlt-7"
  if [ -d "$SRC/mlt-win/share/mlt-7" ]; then
    cp -r "$SRC/mlt-win/share/mlt-7/"* "$PREFIX/share/mlt-7/" 2>/dev/null || true
  fi

  # validasi akhir
  MELT_PATH=$(find "$PREFIX" "$SRC/mlt-win" -name "melt.exe" 2>/dev/null | head -1)
  if [ -z "$MELT_PATH" ]; then
    echo "❌ melt.exe NOT FOUND"
    find "$PREFIX" "$SRC/mlt-win" -name "*melt*" || true
    exit 1
  else
    echo "✅ melt.exe found: $MELT_PATH"
  fi

  echo "✅ lib/mlt-7 modules: $(ls $PREFIX/lib/mlt-7 | wc -l) files"
  echo "✅ share/mlt-7 data: $(ls $PREFIX/share/mlt-7 | wc -l) files"

  echo "[OK] MLT"
}
# ─── MAIN ───────────────────────────────────────────────────────────────────
echo "================================================"
echo " MLT Windows Cross Compile - Ubuntu/GH Actions"
echo "================================================"
echo " PREFIX : $PREFIX"
echo " SRC    : $SRC"
echo " JOBS   : $JOBS"
echo "================================================"

setup_cross_env

build_zlib
build_libiconv
build_xz
build_libxml2
build_pcre2        # wajib sebelum glib di Ubuntu
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
echo " DONE!"
echo " melt.exe : $PREFIX/bin/melt.exe"
echo " DLLs     : $PREFIX/bin/"
echo "================================================"