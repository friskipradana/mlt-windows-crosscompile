# MLT Cross Compile for Windows (Alpine WSL)

Cross compile [MLT Framework](https://www.mltframework.org/) (`melt.exe`) for Windows from Alpine WSL using mingw-w64.

## Background

MLT is a multimedia framework primarily designed for Linux. Building it natively on Windows via MSYS2 results in various bugs:
- Green noise / interlaced frame rendering issues
- Segfault on avformat consumer
- XML + consumer crash

This guide cross compiles MLT from Alpine WSL, producing a stable `melt.exe` for Windows.

## Requirements

- Windows 11/10 with WSL2
- Alpine Linux WSL
- Internet connection

## Setup Alpine WSL

```bash
# Install cross compiler and build tools
apk add \
  mingw-w64-gcc mingw-w64-binutils mingw-w64-headers \
  mingw-w64-crt mingw-w64-winpthreads \
  cmake make ninja meson \
  nasm yasm \
  pkgconfig \
  python3 perl \
  autoconf automake libtool \
  gettext-dev gperf \
  git wget

# Install meson latest via pip
pip3 install meson
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
```

## Directory Structure

```
~/tools/
├── src/          ← source code semua dependency
├── win-deps/     ← hasil build (DLL, headers, libs)
└── mingw-cross.ini  ← meson cross file
```

```bash
mkdir -p ~/tools/src ~/tools/win-deps
```

## Meson Cross File

Buat file `~/tools/mingw-cross.ini`:

```ini
[binaries]
c = 'x86_64-w64-mingw32-gcc'
cpp = 'x86_64-w64-mingw32-g++'
ar = 'x86_64-w64-mingw32-ar'
strip = 'x86_64-w64-mingw32-strip'
windres = 'x86_64-w64-mingw32-windres'
pkgconfig = 'pkg-config'

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[properties]
pkg_config_libdir = '/home/YOUR_USER/tools/win-deps/lib/pkgconfig'
```

## Build Dependencies

### 1. zlib
```bash
cd ~/tools/src
wget https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
tar -xzf zlib-1.3.1.tar.gz && cd zlib-1.3.1
mkdir build && cd build
cmake .. \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
  -DCMAKE_INSTALL_PREFIX=~/tools/win-deps \
  -DBUILD_SHARED_LIBS=ON
make -j$(nproc) && make install
```

### 2. libiconv
```bash
cd ~/tools/src
wget https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz
tar -xzf libiconv-1.17.tar.gz && cd libiconv-1.17
./configure \
  --host=x86_64-w64-mingw32 \
  --prefix=~/tools/win-deps \
  --enable-shared --disable-static
make -j$(nproc) && make install
```

### 3. liblzma (xz)
```bash
cd ~/tools/src
wget https://github.com/tukaani-project/xz/releases/download/v5.4.6/xz-5.4.6.tar.gz
tar -xzf xz-5.4.6.tar.gz && cd xz-5.4.6
./configure \
  --host=x86_64-w64-mingw32 \
  --prefix=~/tools/win-deps \
  --enable-shared --disable-static
make -j$(nproc) && make install
```

### 4. libxml2
```bash
cd ~/tools/src
wget https://download.gnome.org/sources/libxml2/2.12/libxml2-2.12.0.tar.xz
tar -xf libxml2-2.12.0.tar.xz && cd libxml2-2.12.0
mkdir build && cd build
cmake .. \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
  -DCMAKE_INSTALL_PREFIX=~/tools/win-deps \
  -DCMAKE_PREFIX_PATH=~/tools/win-deps \
  -DBUILD_SHARED_LIBS=ON \
  -DLIBXML2_WITH_ICONV=ON \
  -DLIBXML2_WITH_ZLIB=ON \
  -DLIBXML2_WITH_LZMA=ON \
  -DLIBXML2_WITH_PYTHON=OFF
make -j$(nproc) && make install
```

### 5. glib
```bash
cd ~/tools/src
wget https://download.gnome.org/sources/glib/2.78/glib-2.78.0.tar.xz
tar -xf glib-2.78.0.tar.xz && cd glib-2.78.0
mkdir build && cd build
meson setup .. \
  --prefix=~/tools/win-deps \
  --cross-file ~/tools/mingw-cross.ini
ninja -j$(nproc) && ninja install
```

### 6. freetype
```bash
cd ~/tools/src
wget https://download.savannah.gnu.org/releases/freetype/freetype-2.13.2.tar.gz
tar -xzf freetype-2.13.2.tar.gz && cd freetype-2.13.2
mkdir build && cd build
cmake .. \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
  -DCMAKE_INSTALL_PREFIX=~/tools/win-deps \
  -DCMAKE_PREFIX_PATH=~/tools/win-deps \
  -DBUILD_SHARED_LIBS=ON
make -j$(nproc) && make install
```

### 7. expat
```bash
cd ~/tools/src
wget https://github.com/libexpat/libexpat/releases/download/R_2_5_0/expat-2.5.0.tar.gz
tar -xzf expat-2.5.0.tar.gz && cd expat-2.5.0
./configure \
  --host=x86_64-w64-mingw32 \
  --prefix=~/tools/win-deps \
  --enable-shared --disable-static
make -j$(nproc) && make install
```

### 8. fontconfig
```bash
cd ~/tools/src
wget https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.15.0.tar.gz
tar -xzf fontconfig-2.15.0.tar.gz && cd fontconfig-2.15.0
./configure \
  --host=x86_64-w64-mingw32 \
  --prefix=~/tools/win-deps \
  --enable-shared --disable-static \
  PKG_CONFIG_PATH=~/tools/win-deps/lib/pkgconfig
make -j$(nproc)
make install-data install-exec  # skip fc-cache karena tidak bisa run di Linux
```

### 9. harfbuzz
```bash
cd ~/tools/src
wget https://github.com/harfbuzz/harfbuzz/releases/download/8.3.0/harfbuzz-8.3.0.tar.xz
tar -xf harfbuzz-8.3.0.tar.xz && cd harfbuzz-8.3.0
mkdir build && cd build
meson setup .. \
  --prefix=~/tools/win-deps \
  --cross-file ~/tools/mingw-cross.ini \
  -Dtests=disabled -Ddocs=disabled
ninja -j$(nproc) && ninja install
```

### 10. pango
```bash
cd ~/tools/src
wget https://download.gnome.org/sources/pango/1.51/pango-1.51.0.tar.xz
tar -xf pango-1.51.0.tar.xz && cd pango-1.51.0
mkdir build && cd build
meson setup .. \
  --prefix=~/tools/win-deps \
  --cross-file ~/tools/mingw-cross.ini \
  -Dcairo=disabled
ninja -j$(nproc) && ninja install
```

### 11. libsamplerate
```bash
cd ~/tools/src
wget https://github.com/libsndfile/libsamplerate/archive/refs/tags/0.2.2.tar.gz \
  -O libsamplerate-0.2.2.tar.gz
tar -xzf libsamplerate-0.2.2.tar.gz && cd libsamplerate-0.2.2
mkdir build && cd build
cmake .. \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
  -DCMAKE_INSTALL_PREFIX=~/tools/win-deps \
  -DBUILD_SHARED_LIBS=ON \
  -DLIBSAMPLERATE_EXAMPLES=OFF \
  -DLIBSAMPLERATE_TESTS=OFF
make -j$(nproc) && make install
```

### 12. rubberband
```bash
cd ~/tools/src
wget https://breakfastquay.com/files/releases/rubberband-3.3.0.tar.bz2
tar -xjf rubberband-3.3.0.tar.bz2 && cd rubberband-3.3.0
mkdir build && cd build
meson setup .. \
  --prefix=~/tools/win-deps \
  --cross-file ~/tools/mingw-cross.ini \
  -Dfft=builtin -Dresampler=builtin
ninja -j$(nproc) && ninja install
```

### 13. x264
```bash
cd ~/tools/src
wget https://code.videolan.org/videolan/x264/-/archive/master/x264-master.tar.gz
tar -xzf x264-master.tar.gz && cd x264-master
./configure \
  --host=x86_64-w64-mingw32 \
  --prefix=~/tools/win-deps \
  --enable-shared --disable-static --disable-cli \
  --cross-prefix=x86_64-w64-mingw32-
make -j$(nproc) && make install
```

### 14. FFmpeg
```bash
cd ~/tools/src
wget https://ffmpeg.org/releases/ffmpeg-7.1.tar.gz
tar -xzf ffmpeg-7.1.tar.gz && cd ffmpeg-7.1
PKG_CONFIG_PATH=~/tools/win-deps/lib/pkgconfig \
PKG_CONFIG_LIBDIR=~/tools/win-deps/lib/pkgconfig \
./configure \
  --cross-prefix=x86_64-w64-mingw32- \
  --arch=x86_64 \
  --target-os=mingw32 \
  --prefix=~/tools/win-deps \
  --enable-shared --disable-static \
  --enable-gpl --enable-libx264 \
  --pkg-config=pkg-config \
  --pkg-config-flags="--define-prefix" \
  --extra-cflags="-I~/tools/win-deps/include" \
  --extra-ldflags="-L~/tools/win-deps/lib" \
  --extra-libs="-lx264"
make -j$(nproc) && make install
```

### 15. SDL2
```bash
cd ~/tools/src
wget https://github.com/libsdl-org/SDL/releases/download/release-2.30.0/SDL2-2.30.0.tar.gz
tar -xzf SDL2-2.30.0.tar.gz && cd SDL2-2.30.0
mkdir build && cd build
cmake .. \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
  -DCMAKE_INSTALL_PREFIX=~/tools/win-deps \
  -DBUILD_SHARED_LIBS=ON
make -j$(nproc) && make install
```

### 16. libexif
```bash
cd ~/tools/src
wget https://github.com/libexif/libexif/releases/download/v0.6.25/libexif-0.6.25.tar.xz
tar -xf libexif-0.6.25.tar.xz && cd libexif-0.6.25
./configure \
  --host=x86_64-w64-mingw32 \
  --prefix=~/tools/win-deps \
  --enable-shared --disable-static
make -j$(nproc) && make install
```

### 17. libebur128
```bash
cd ~/tools/src
git clone https://github.com/jiixyj/libebur128.git
cd libebur128
mkdir build && cd build
cmake .. \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
  -DCMAKE_INSTALL_PREFIX=~/tools/win-deps \
  -DBUILD_SHARED_LIBS=ON
make -j$(nproc) && make install
```

### 18. dlfcn-win32
```bash
cd ~/tools/src
git clone https://github.com/dlfcn-win32/dlfcn-win32.git
cd dlfcn-win32
mkdir build && cd build
cmake .. \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
  -DCMAKE_INSTALL_PREFIX=~/tools/win-deps \
  -DBUILD_SHARED_LIBS=ON
make -j$(nproc) && make install
```

## Build MLT

```bash
cd ~/tools/src
git clone https://github.com/mltframework/mlt.git mlt-win
cd mlt-win

# Fix io.c untuk Alpine musl libc
sed -i '1s/^/#include <sys\/select.h>\n/' src/melt/io.c

mkdir build && cd build
cmake .. \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
  -DCMAKE_INSTALL_PREFIX=~/tools/win-deps \
  -DCMAKE_PREFIX_PATH=~/tools/win-deps \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXE_LINKER_FLAGS="-L~/tools/win-deps/lib" \
  -DCMAKE_SHARED_LINKER_FLAGS="-L~/tools/win-deps/lib" \
  -DCMAKE_C_FLAGS="-I~/tools/win-deps/include" \
  -DCMAKE_CXX_FLAGS="-I~/tools/win-deps/include" \
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

make -j$(nproc) && make install
```

## Test di Windows

Copy hasil build ke Windows:
```bash
cp -r ~/tools/win-deps /mnt/c/Users/YOUR_USER/Desktop/mlt-windows
```

Test di PowerShell:
```powershell
cd C:\Users\YOUR_USER\Desktop\mlt-windows
.\melt.exe --version
```

## Known Issues

- `MOD_QT6=OFF` — Qt6 cross compile tidak didukung, gunakan `DMOD_QT6=OFF`
- `MOD_GDK=OFF` — GDK/GTK cross compile bermasalah
- `MOD_JACKRACK=OFF` — JACK tidak tersedia di Windows
- `io.c` perlu patch `#include <sys/select.h>` untuk Alpine musl libc
- fontconfig install dengan `make install-data install-exec` bukan `make install` karena `fc-cache.exe` tidak bisa run di Linux

## License

MLT Framework is licensed under LGPLv2.1. See [MLT License](https://www.mltframework.org/license/).
