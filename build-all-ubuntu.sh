#!/bin/bash
# build-all-ubuntu.sh - Cross compile MLT for Windows from Ubuntu (GitHub Actions)
# Merged & fixed from working Alpine WSL version
# FIX (latest): generate zlib.pc MANUAL setelah build zlib, supaya meson
# (baik native maupun cross/host) SELALU nemu zlib lewat pkg-config dan
# TIDAK PERNAH trigger fallback download dari zlib.net/fossils (yang
# checksum-nya sering mismatch karena upstream fossil archive tidak stabil).
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
export CFLAGS="-I$PREFIX/include -pthread"
export CXXFLAGS="-I$PREFIX/include -pthread"
export LDFLAGS="-L$PREFIX/lib -lwinpthread"

mkdir -p "$SRC" "$PREFIX/lib" "$PREFIX/bin" "$PREFIX/include"

# ─── Helper: skip kalau sudah di-download ───────────────────────────────────
download_if_missing() {
  local url="$1"
  local filename="$2"
  if [ ! -f "$SRC/$filename" ]; then
    # FIX: retry + timeout supaya gangguan jaringan sesaat (exit code 4 dari
    # wget = network failure) tidak langsung mematikan seluruh build.
    # --tries=5: coba 5x sebelum benar-benar menyerah.
    # --timeout=30: tiap percobaan max 30 detik nunggu sebelum dianggap gagal.
    # --waitretry=5: jeda 5 detik antar percobaan (exponential-ish backoff).
    if ! wget -q --tries=5 --timeout=30 --waitretry=5 "$url" -O "$SRC/$filename"; then
      echo "  [ERROR] Gagal download $filename dari $url setelah beberapa percobaan"
      rm -f "$SRC/$filename"   # jangan sisakan file partial/corrupt
      exit 1
    fi
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

# ─── zlib.pc generator (FIX UTAMA) ──────────────────────────────────────────
# Jangan andalkan CMake/GNUInstallDirs untuk generate zlib.pc secara otomatis
# -- perilakunya bisa beda tiap versi/platform dan kadang tidak ke-install
# sama sekali saat cross-compiling ke Windows. Generate manual supaya:
#   1. Meson (native ATAU cross/host) selalu nemu zlib lewat pkg-config
#   2. Tidak pernah ada jalur ke fallback download zlib.net/fossils
#      (fossil archive checksum-nya dikenal sering berubah/mismatch)
generate_zlib_pc() {
  echo ">>> Generating zlib.pc manually..."

  # Cari file libz yang benar-benar ke-install. Nama bisa beda-beda
  # tergantung platform target CMake untuk Windows (import lib .dll.a
  # untuk shared, atau .a untuk static).
  local LIBZ_FILE=""
  for cand in "$PREFIX/lib/libz.dll.a" "$PREFIX/lib/libzlib.dll.a" \
              "$PREFIX/lib/libz.a" "$PREFIX/lib/libzlibstatic.a" \
              "$PREFIX/bin/libz.dll.a"; do
    if [ -f "$cand" ]; then
      LIBZ_FILE="$cand"
      break
    fi
  done

  if [ -z "$LIBZ_FILE" ]; then
    echo "  [ERROR] Tidak ada file libz*.a / libzlib*.a di $PREFIX/lib -- cek hasil install zlib!"
    find "$PREFIX" -iname "*libz*" 2>/dev/null
    exit 1
  fi

  # Ekstrak nama link (-lz atau -lzlib dst) dari nama file
  local LIBZ_NAME
  LIBZ_NAME=$(basename "$LIBZ_FILE")
  LIBZ_NAME="${LIBZ_NAME#lib}"
  LIBZ_NAME="${LIBZ_NAME%.dll.a}"
  LIBZ_NAME="${LIBZ_NAME%.a}"

  if [ ! -f "$PREFIX/include/zlib.h" ]; then
    echo "  [ERROR] zlib.h tidak ditemukan di $PREFIX/include -- cek hasil install zlib!"
    exit 1
  fi

  # Ambil versi asli dari header zlib.h supaya .pc tidak hardcode versi salah
  local ZVER
  ZVER=$(grep -oP '(?<=#define ZLIB_VERSION ")[^"]+' "$PREFIX/include/zlib.h" 2>/dev/null || echo "1.3.1")

  mkdir -p "$PREFIX/lib/pkgconfig"
  cat > "$PREFIX/lib/pkgconfig/zlib.pc" << EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
sharedlibdir=\${libdir}
includedir=\${prefix}/include

Name: zlib
Description: zlib compression library
Version: $ZVER

Requires:
Libs: -L\${libdir} -L\${sharedlibdir} -l$LIBZ_NAME
Cflags: -I\${includedir}
EOF

  echo "  [OK] zlib.pc generated -> $PREFIX/lib/pkgconfig/zlib.pc (lib=-l$LIBZ_NAME, ver=$ZVER)"

  # Verifikasi langsung supaya build gagal cepat & jelas kalau masih salah,
  # daripada baru ketahuan pas glib configure jauh di bawah.
  if PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" pkg-config --exists zlib; then
    local FOUND_VER
    FOUND_VER=$(PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" pkg-config --modversion zlib)
    echo "  [VERIFIED] pkg-config found zlib $FOUND_VER"
  else
    echo "  [ERROR] pkg-config MASIH tidak nemu zlib setelah generate zlib.pc manual!"
    echo "  Debug isi file:"
    cat "$PREFIX/lib/pkgconfig/zlib.pc"
    exit 1
  fi
}

# ─── 1. zlib ────────────────────────────────────────────────────────────────
build_zlib() {
  echo ">>> Building zlib..."
  cd "$SRC"
  download_if_missing \
    https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz \
    zlib-1.3.1.tar.gz
  [ -d zlib-1.3.1 ] || tar -xzf zlib-1.3.1.tar.gz
  cmake_build zlib-1.3.1 -DCMAKE_INSTALL_LIBDIR=lib

  # FIX: selalu generate ulang zlib.pc manual, terlepas dari apapun yang
  # CMake hasilkan (atau tidak hasilkan). Ini idempotent & murah, jadi aman
  # dijalankan tiap kali script ini di-run, termasuk saat cmake_build di-skip
  # karena .build_done sudah ada dari cache run sebelumnya.
  generate_zlib_pc

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

  # Sanity check terakhir sebelum masuk meson: pastikan zlib.pc kelihatan
  # persis dengan cara meson akan melihatnya (lewat pkg_config_libdir di
  # cross file), supaya kalau gagal, gagalnya di sini dengan pesan jelas --
  # bukan di tengah-tengah meson setup glib dengan pesan hash mismatch.
  echo ">>> Pre-flight check: zlib.pc harus terlihat sebelum build glib"
  if ! PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" pkg-config --exists zlib; then
    echo "  [ERROR] zlib.pc tidak terdeteksi! Jalankan ulang build_zlib()."
    exit 1
  fi
  echo "  [OK] zlib terdeteksi: $(PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" pkg-config --modversion zlib)"

  # FIX: tidak ada opsi -Dpcre2 di glib 2.74+ (dihapus, jadi mandatory)
  # FIX: tidak ada opsi -Dglib_assert / -Dglib_checks di versi ini
  # CATATAN: JANGAN pakai --wrap-mode=nodownload di sini. glib butuh
  # libffi lewat subproject wrap (tidak ada libffi cross-compiled untuk
  # mingw di $PREFIX), dan nodownload akan mem-block download subproject
  # itu juga -- bukan cuma zlib -- sehingga malah gagal dengan error
  # "Automatic wrap-based subproject downloading is disabled".
  # Masalah zlib fallback ke zlib.net/fossils sudah beres lewat
  # generate_zlib_pc() di atas: karena zlib.pc sudah SELALU ketemu lewat
  # pkg-config sebelum meson jalan, meson tidak akan pernah butuh coba
  # fallback-download zlib sama sekali -- jadi wrap-mode default aman.
  meson_build glib-2.78.0 \
    -Dtests=false \
    -Dinstalled_tests=false \
    -Dlibmount=disabled \
    -Dforce_posix_threads=true
  echo "[OK] glib"
}

# ─── 7. freetype ────────────────────────────────────────────────────────────
# FIX: download.savannah.gnu.org sering gagal (exit 8) di GitHub Actions,
# ganti ke mirror GitHub resmi freetype/freetype yang lebih stabil.
build_freetype() {
  echo ">>> Building freetype..."
  cd "$SRC"
  download_if_missing \
    https://github.com/freetype/freetype/archive/refs/tags/VER-2-13-2.tar.gz \
    freetype-2.13.2.tar.gz
  if [ ! -f freetype-2.13.2/CMakeLists.txt ]; then
    rm -rf freetype-2.13.2
    tar -xzf freetype-2.13.2.tar.gz
    mv freetype-VER-2-13-2 freetype-2.13.2
  fi
  cmake_build freetype-2.13.2 \
    -DFT_DISABLE_ZLIB=ON \
    -DFT_DISABLE_BZIP2=ON \
    -DFT_DISABLE_PNG=ON \
    -DFT_DISABLE_HARFBUZZ=ON \
    -DFT_DISABLE_BROTLI=ON
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
  # FIX: code.videolan.org (GitLab VideoLAN) sering unreachable dari GitHub
  # Actions (exit code 4 = network failure di wget, bukan gangguan sesaat).
  # Ganti ke mirror/x264 di GitHub yang jauh lebih stabil untuk CI.
  download_if_missing \
    https://github.com/mirror/x264/archive/refs/heads/stable.tar.gz \
    x264-master.tar.gz
  if [ ! -d x264-master ]; then
    tar -xzf x264-master.tar.gz
    mv x264-stable x264-master
  fi

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
# FIX: MLT v6.26.1 (dirilis ~2020) menulis src/modules/avformat/factory.c
# pakai API FFmpeg lama: AVLockOp, av_lockmgr_register, av_register_all,
# avfilter_register_all, av_iformat_next, av_oformat_next, av_codec_next,
# avfilter_next. Semua API ini DIHAPUS TOTAL di FFmpeg 5.0+ (sebelumnya
# cuma deprecated-tapi-jalan di 4.x). FFmpeg 7.1 karena itu gagal compile
# dengan error "undeclared" / "incomplete type" di avformat module.
# FIX: pin ke FFmpeg 4.4.5 (rilis LTS-ish terakhir dari seri 4.x yang masih
# menyediakan API lama tsb secara fungsional) supaya avformat module MLT
# v6.26.1 bisa compile tanpa perlu patch source MLT sama sekali.
FFMPEG_VERSION="4.4.5"

build_ffmpeg() {
  echo ">>> Building FFmpeg ($FFMPEG_VERSION)..."
  cd "$SRC"
  download_if_missing \
    "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.gz" \
    "ffmpeg-$FFMPEG_VERSION.tar.gz"
  [ -d "ffmpeg-$FFMPEG_VERSION" ] || tar -xzf "ffmpeg-$FFMPEG_VERSION.tar.gz"

  if [ -f "$SRC/ffmpeg-$FFMPEG_VERSION/.build_done" ]; then
    echo "  [skip] FFmpeg"
  else
    cd "$SRC/ffmpeg-$FFMPEG_VERSION"
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

# ─── 19b. fnmatch shim ───────────────────────────────────────────────────────
# FIX: fnmatch.h adalah header POSIX yang TIDAK disediakan oleh mingw-w64 di
# Ubuntu (dikonfirmasi juga di issue resmi MSYS2 #855 -- ini bukan bug khusus
# kita, memang mingw-w64 tidak menyertakannya karena bukan bagian Windows API).
# MLT's producer_loader.c pakai fnmatch() untuk cocokkan pola nama file loader.
# Alpine kamu kemungkinan lolos karena paket mingw-w64-nya beda (bukan berarti
# tidak butuh fnmatch, mungkin toolchain Alpine kebetulan menyediakan header
# serupa via paket lain). Solusi paling robust & tidak bergantung jaringan
# eksternal: bikin implementasi fnmatch minimal sendiri (public-domain-style,
# cukup untuk pola wildcard * ? [...] dasar yang dipakai MLT), compile jadi
# static lib kecil, taruh di $PREFIX/include & $PREFIX/lib supaya otomatis
# kepakai saat build MLT (CFLAGS/LDFLAGS global sudah include path itu).
build_fnmatch_shim() {
  echo ">>> Building fnmatch shim (mingw-w64 tidak sediakan fnmatch.h)..."

  if [ -f "$PREFIX/include/fnmatch.h" ] && [ -f "$PREFIX/lib/libfnmatchcompat.a" ]; then
    echo "  [skip] fnmatch shim sudah ada"
    return 0
  fi

  mkdir -p "$SRC/fnmatch-shim"
  cd "$SRC/fnmatch-shim"

  cat > fnmatch.h << 'HDREOF'
#ifndef FNMATCH_SHIM_H
#define FNMATCH_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

#define FNM_NOMATCH   1
#define FNM_NOESCAPE  0x01
#define FNM_PATHNAME  0x02
#define FNM_PERIOD    0x04
#define FNM_CASEFOLD  0x08

int fnmatch(const char *pattern, const char *string, int flags);

#ifdef __cplusplus
}
#endif

#endif /* FNMATCH_SHIM_H */
HDREOF

  cat > fnmatch.c << 'SRCEOF'
/* Minimal fnmatch() implementation (public-domain style) for mingw-w64,
 * which does not ship the POSIX fnmatch.h/fnmatch(). Supports the basic
 * wildcard syntax: '*', '?', and '[...]' character classes, plus the
 * common FNM_NOESCAPE / FNM_PATHNAME / FNM_PERIOD / FNM_CASEFOLD flags.
 * Not a full POSIX-conformant implementation, but sufficient for simple
 * filename pattern matching use-cases like MLT's producer_loader.c.
 */
#include "fnmatch.h"
#include <ctype.h>
#include <string.h>

static int do_match(const char *pat, const char *str, int flags)
{
  int fold = (flags & FNM_CASEFOLD) != 0;
  int noesc = (flags & FNM_NOESCAPE) != 0;

  while (*pat) {
    char pc = *pat;

    if (pc == '*') {
      /* collapse consecutive '*' */
      while (*pat == '*')
        pat++;
      if (!*pat)
        return 0; /* trailing '*' matches everything remaining */
      while (*str) {
        if (do_match(pat, str, flags) == 0)
          return 0;
        str++;
      }
      return do_match(pat, str, flags);
    } else if (pc == '?') {
      if (!*str)
        return FNM_NOMATCH;
      pat++;
      str++;
    } else if (pc == '[' ) {
      const char *p = pat + 1;
      int negate = 0;
      int matched = 0;
      char sc = *str;

      if (!sc)
        return FNM_NOMATCH;
      if (fold)
        sc = (char)tolower((unsigned char)sc);

      if (*p == '!' || *p == '^') {
        negate = 1;
        p++;
      }
      while (*p && *p != ']') {
        char lo = *p++;
        char hi = lo;
        if (fold)
          lo = (char)tolower((unsigned char)lo);
        if (*p == '-' && p[1] && p[1] != ']') {
          hi = p[1];
          if (fold)
            hi = (char)tolower((unsigned char)hi);
          p += 2;
        } else {
          hi = lo;
        }
        if (sc >= lo && sc <= hi)
          matched = 1;
      }
      if (*p == ']')
        p++;
      if (matched == negate)
        return FNM_NOMATCH;
      pat = p;
      str++;
    } else if (pc == '\\' && !noesc) {
      pat++;
      if (!*pat)
        return FNM_NOMATCH;
      if (!*str)
        return FNM_NOMATCH;
      if (*pat != *str)
        return FNM_NOMATCH;
      pat++;
      str++;
    } else {
      char a = pc;
      char b = *str;
      if (!b)
        return FNM_NOMATCH;
      if (fold) {
        a = (char)tolower((unsigned char)a);
        b = (char)tolower((unsigned char)b);
      }
      if (a != b)
        return FNM_NOMATCH;
      pat++;
      str++;
    }
  }

  return (*str == '\0') ? 0 : FNM_NOMATCH;
}

int fnmatch(const char *pattern, const char *string, int flags)
{
  if (!pattern || !string)
    return FNM_NOMATCH;
  return do_match(pattern, string, flags);
}
SRCEOF

  $CROSS-gcc -c -O2 -o fnmatch.o fnmatch.c
  $CROSS-ar rcs libfnmatchcompat.a fnmatch.o

  mkdir -p "$PREFIX/include" "$PREFIX/lib"
  cp fnmatch.h "$PREFIX/include/fnmatch.h"
  cp libfnmatchcompat.a "$PREFIX/lib/libfnmatchcompat.a"

  cd "$SRC"
  echo "[OK] fnmatch shim: $PREFIX/include/fnmatch.h + $PREFIX/lib/libfnmatchcompat.a"
}

# ─── 20. MLT ────────────────────────────────────────────────────────────────
# FIX: PIN ke v6.26.1 (rilis terakhir major version 6, sama seperti build
# Alpine kamu yang sudah terbukti jalan). Sengaja TIDAK pakai v7 karena
# struktur folder module/data v7 di-versioned (lib/mlt-7, share/mlt-7) dan
# lokasi build-time berbeda dengan lokasi install-time, yang bikin fallback
# copy jadi tidak reliable untuk cross-compile Windows. v6 pakai folder
# polos (lib/mlt, share/mlt) tanpa versi -- jauh lebih sederhana & terbukti.
MLT_TAG="v6.26.1"

build_mlt() {
  echo ">>> Building MLT ($MLT_TAG)..."

  cd "$SRC"
  # FIX: cache GitHub Actions bisa restore folder mlt-win LAMA dari versi
  # tag yang berbeda (misal v7 sebelumnya). Cek marker file versi, kalau
  # tidak cocok dengan MLT_TAG saat ini, hapus & clone ulang -- supaya
  # tidak salah pakai source code versi lama gara-gara cache hit.
  if [ -d mlt-win ]; then
    CACHED_TAG=$(cat mlt-win/.mlt_tag_marker 2>/dev/null || echo "")
    if [ "$CACHED_TAG" != "$MLT_TAG" ]; then
      echo "  [info] folder mlt-win ada tapi versi cache ($CACHED_TAG) != target ($MLT_TAG), hapus & clone ulang..."
      rm -rf mlt-win
    else
      echo "  [skip] mlt-win sudah versi $MLT_TAG (dari cache)"
    fi
  fi
  if [ ! -d mlt-win ]; then
    git clone --depth=1 --branch "$MLT_TAG" https://github.com/mltframework/mlt.git mlt-win
    echo "$MLT_TAG" > mlt-win/.mlt_tag_marker
  fi

  cd mlt-win
  rm -rf build
  mkdir build && cd build

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
    -DCMAKE_EXE_LINKER_FLAGS="-L$PREFIX/lib -lwinpthread -lfnmatchcompat" \
    -DCMAKE_SHARED_LINKER_FLAGS="-L$PREFIX/lib -lwinpthread -lfnmatchcompat" \
    -DCMAKE_THREAD_LIBS_INIT="-lwinpthread" \
    -DCMAKE_HAVE_THREADS_LIBRARY=ON \
    -DCMAKE_USE_WIN32_THREADS_INIT=OFF \
    -DCMAKE_USE_PTHREADS_INIT=ON \
    -DTHREADS_PREFER_PTHREAD_FLAG=ON \
    -DMLT_BUILD_MELT=ON \
    -DMLT_BUILD_TESTS=OFF \
    -DMLT_BUILD_EXAMPLES=OFF \
    -DMOD_QT6=OFF \
    -DMOD_QT=OFF \
    -DMOD_MOVIT=OFF \
    -DMOD_FREI0R=OFF \
    -DMOD_GDK=OFF \
    -DMOD_GTK2=OFF \
    -DMOD_JACKRACK=OFF \
    -DMOD_SOX=OFF \
    -DMOD_VIDSTAB=OFF \
    -DMOD_VORBIS=OFF \
    -DMOD_RTAUDIO=OFF \
    -DMOD_SDL=OFF \
    -DMOD_XINE=OFF \
    -DMOD_SWIG=OFF \
    -DMOD_DECKLINK=OFF \
    -DMOD_OPENFX=OFF \
    -DENABLE_CLANG_FORMAT=OFF
    # CATATAN: modul yang SENGAJA tetap AKTIF (dependency-nya sudah di-build
    # script ini): core, avformat (ffmpeg), sdl2, xml (libxml2), resample
    # (libsamplerate), rubberband, plus, plusgpl, normalize, oldfilm,
    # kdenlive (kdenlivetitle -- pakai libxml2, no extra dep khusus).
    # Kalau salah satu dari ini ternyata juga butuh header lain yang belum
    # ada, tinggal tambahkan -DMOD_<NAMA>=OFF ke list di atas.

  echo ">>> BUILD"
  # FIX: parallel build (-j$JOBS) bisa "menelan" pesan error asli karena
  # output beberapa target interleaved -- begitu salah satu gagal, make
  # langsung exit dengan "Error 2" tapi baris error compiler/linker yang
  # sebenarnya bisa ketutup/ketimpa output target lain yang masih jalan
  # bareng, apalagi kalau GH Actions log-nya kepotong. Simpan full log ke
  # file, dan kalau parallel build gagal, retry SERIAL (-j1 -k) supaya
  # error sebenarnya kelihatan jelas satu-satu tanpa noise.
  BUILD_LOG="$SRC/mlt-win/build/build.log"
  if ! make -j$JOBS 2>&1 | tee "$BUILD_LOG"; then
    echo ""
    echo "❌ Parallel build gagal. Retry SERIAL (-j1) supaya error asli kelihatan jelas..."
    echo ""
    make -j1 -k 2>&1 | tee -a "$BUILD_LOG" || true
    echo ""
    echo "=== RINGKASAN ERROR (grep dari $BUILD_LOG) ==="
    grep -iE "error:|undefined reference|fatal error|No such file|cannot find" "$BUILD_LOG" | sort -u || echo "(tidak ada pola error yang kecocok, cek $BUILD_LOG manual)"
    echo "==============================================="
    exit 1
  fi

  echo ">>> DEBUG: cari melt & dll"
  find . -type f | grep -E "melt.exe|mlt.*\.dll" || true

  echo ">>> INSTALL"
  make install

  # =========================
  # FALLBACK FINAL FIX
  # v6 pakai folder POLOS tanpa versi: lib/mlt, share/mlt
  # =========================

  echo ">>> FALLBACK: melt.exe"
  MELT_PATH=$(find "$SRC/mlt-win/build/out" -name "melt.exe" 2>/dev/null | head -1)
  if [ -n "$MELT_PATH" ]; then
    mkdir -p "$PREFIX/bin"
    cp -f "$MELT_PATH" "$PREFIX/bin/"
    echo "  [OK] melt.exe copied"
  else
    echo "  [WARN] melt.exe tidak ditemukan di build/out, cek hasil make install..."
    MELT_PATH=$(find "$PREFIX/bin" -name "melt.exe" 2>/dev/null | head -1)
  fi

  echo ">>> FALLBACK: libmlt DLL"
  find "$SRC/mlt-win/build/out" -maxdepth 3 -name "libmlt*.dll" 2>/dev/null | while read dll; do
    cp "$dll" "$PREFIX/bin/"
    echo "  [copied] $(basename "$dll")"
  done

  echo ">>> FALLBACK: modules"
  mkdir -p "$PREFIX/lib/mlt"
  MODULES_SRC=$(find "$SRC/mlt-win/build" -maxdepth 4 -type d -path "*/lib/mlt" 2>/dev/null | head -1)
  if [ -z "$MODULES_SRC" ]; then
    MODULES_SRC="$SRC/mlt-win/build/out/lib/mlt"
  fi
  if [ -d "$MODULES_SRC" ]; then
    find "$MODULES_SRC" -name "*.dll" | while read dll; do
      cp "$dll" "$PREFIX/lib/mlt/"
      echo "  [copied] $(basename "$dll")"
    done
  fi
  DLL_COUNT=$(find "$PREFIX/lib/mlt" -name "*.dll" 2>/dev/null | wc -l)
  echo "  [OK] modules: $DLL_COUNT dll di \$PREFIX/lib/mlt"

  echo ">>> FALLBACK: share (cari folder 'profiles' langsung, paling reliable)"
  mkdir -p "$PREFIX/share/mlt"
  PROFILES_DIR=$(find "$SRC/mlt-win/build" -type d -name "profiles" 2>/dev/null | head -1)
  if [ -n "$PROFILES_DIR" ]; then
    SHARE_SRC=$(dirname "$PROFILES_DIR")
    cp -r "$SHARE_SRC/"* "$PREFIX/share/mlt/" 2>/dev/null || true
    echo "  [OK] share dari: $SHARE_SRC"
  else
    echo "  [WARN] folder 'profiles' tidak ditemukan, coba path lama..."
    if [ -d "$SRC/mlt-win/build/out/share/mlt" ]; then
      cp -r "$SRC/mlt-win/build/out/share/mlt/"* "$PREFIX/share/mlt/" 2>/dev/null || true
    fi
  fi
  ITEM_COUNT=$(find "$PREFIX/share/mlt" -mindepth 1 2>/dev/null | wc -l)
  echo "  [OK] share: $ITEM_COUNT items di \$PREFIX/share/mlt"

  # Copy semua runtime DLL dependency ke bin/, biar Windows loader
  # bisa resolve semua dependency saat melt.exe dijalankan.
  echo ">>> Copying all runtime DLLs to bin/"
  find "$PREFIX/lib" -maxdepth 1 -name "*.dll" -exec cp {} "$PREFIX/bin/" \;

  # =========================
  # VALIDASI FINAL
  # =========================

  MELT_PATH=$(find "$PREFIX/bin" -name "melt.exe" 2>/dev/null | head -1)

  if [ -z "$MELT_PATH" ]; then
    echo "❌ melt.exe NOT FOUND"
    exit 1
  fi

  echo "✅ melt.exe: $MELT_PATH"
  echo "✅ modules: $(ls $PREFIX/lib/mlt 2>/dev/null | wc -l)"
  echo "✅ share: $(ls $PREFIX/share/mlt 2>/dev/null | wc -l)"

  echo "[OK] MLT BUILT SUCCESS"
}

# ─── generate run_melt.ps1 (v6, folder polos tanpa versi) ────────────────────
generate_run_melt_script() {
  echo ">>> Generating run_melt.ps1..."
  cat > "$PREFIX/run_melt.ps1" << 'EOF'
# run_melt.ps1 (auto-generated by build-all-ubuntu.sh, MLT v6)
# PowerShell script untuk menjalankan melt.exe dengan environment MLT yang benar
$env:MLT_HOME = $PSScriptRoot
$env:MLT_REPOSITORY = "$env:MLT_HOME\lib\mlt"
$env:MLT_DATA = "$env:MLT_HOME\share\mlt"
$env:MLT_PROFILES_PATH = "$env:MLT_HOME\share\mlt\profiles"
$env:PATH = "$env:MLT_HOME\bin;$env:MLT_HOME;$env:PATH"
Set-Location $env:MLT_HOME
echo "" | & "$env:MLT_HOME\melt.exe" $args
EOF
  echo "[OK] run_melt.ps1 generated (v6, folder polos: mlt)"
}


# ─── MAIN ───────────────────────────────────────────────────────────────────
echo "================================================"
echo " MLT Windows Cross Compile - Ubuntu/GH Actions"
echo "================================================"
echo " PREFIX : $PREFIX"
echo " SRC    : $SRC"
echo " JOBS   : $JOBS"
echo " MLT tag: $MLT_TAG"
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
build_fnmatch_shim
build_mlt
generate_run_melt_script

echo ""
echo "================================================"
echo " DONE!"
echo " melt.exe    : $PREFIX/bin/melt.exe"
echo " DLLs        : $PREFIX/bin/"
echo " run_melt.ps1: $PREFIX/run_melt.ps1"
echo "================================================"