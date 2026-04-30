# MLT Windows Cross Compile

Cross compile [MLT Framework](https://www.mltframework.org/) (`melt.exe`) for Windows using MinGW-w64.

Supports two build environments:
- **Alpine WSL** — build locally from Windows
- **GitHub Actions (Ubuntu)** — automated CI/CD build


## Background

MLT is a multimedia framework primarily designed for Linux. Building it natively on Windows via MSYS2 results in various bugs:
- Green noise / interlaced frame rendering issues
- Segfault on avformat consumer
- XML + consumer crash

This project cross compiles MLT from Linux using MinGW-w64, producing a stable `melt.exe` for Windows.


## Build Paths

| Environment | Script | Use Case |
|---|---|---|
| Alpine WSL (local) | `build-all-alpine.sh` | Build on your own machine via WSL |
| Ubuntu / GitHub Actions | `build-all-ubuntu.sh` | Automated CI/CD build |


---

## Option A: Alpine WSL (Local)

### Requirements

- Windows 10/11 with WSL2
- Alpine Linux WSL
- Internet connection

### Setup Alpine WSL

```bash
# Install cross compiler and build tools
apk add \
  mingw-w64-gcc mingw-w64-binutils mingw-w64-headers \
  mingw-w64-crt mingw-w64-winpthreads \
  cmake make ninja \
  nasm yasm \
  pkgconfig \
  python3 perl \
  autoconf automake libtool \
  gettext-dev gperf \
  git wget \
  libffi-dev pcre2-dev

# Install latest meson via pip
pip3 install meson
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
```

### Build (Alpine)

```bash
chmod +x build-all-alpine.sh
./build-all-alpine.sh
```


---

## Option B: GitHub Actions (Ubuntu)

### Setup

1. Fork or clone this repo to your GitHub account
2. Push a tag to trigger a release build:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
   Or trigger manually from the **Actions** tab → **Build MLT for Windows** → **Run workflow**

### What the workflow does

```
Checkout → Install tools → Restore cache → Build → Show folder structure → Validate → Package → Upload
```

- Builds on `ubuntu-latest` with MinGW-w64 cross compiler
- Caches `~/tools/win-deps` and `~/tools/src` keyed by hash of `build-all-ubuntu.sh`
- On manual dispatch: uploads `mlt-windows.zip` as a GitHub Artifact
- On tag push: creates a GitHub Release with `mlt-windows.zip` attached

### Cache behavior

The cache key is based on `hashFiles('build-all-ubuntu.sh')`. If the build script changes, the cache is automatically invalidated and all dependencies are rebuilt from scratch. If the script has not changed, cached dependencies are restored and skipped.


---

## Directory Structure

```
~/tools/
├── src/             ← dependency source code & build dirs
├── win-deps/        ← build output (DLLs, headers, libs)
│   ├── bin/         ← melt.exe + all DLLs
│   ├── lib/         ← .dll.a import libs + pkgconfig
│   └── include/     ← headers
└── mingw-cross.ini  ← auto-generated meson cross file
```


---

## Dependencies Built

All dependencies are cross-compiled for Windows (x86_64) in this order:

| # | Library | Version | Build System |
|---|---|---|---|
| 1 | zlib | 1.3.1 | CMake |
| 2 | libiconv | 1.17 | Autoconf |
| 3 | xz / liblzma | 5.4.6 | Autoconf |
| 4 | libxml2 | 2.12.0 | CMake |
| 5 | pcre2 *(Ubuntu only)* | 10.42 | CMake |
| 6 | glib | 2.78.0 | Meson |
| 7 | freetype | 2.13.2 | CMake |
| 8 | expat | 2.5.0 | Autoconf |
| 9 | fontconfig | 2.15.0 | Autoconf |
| 10 | harfbuzz | 8.3.0 | Meson |
| 11 | pango | 1.51.0 | Meson |
| 12 | libsamplerate | 0.2.2 | CMake |
| 13 | rubberband | 3.3.0 | Meson |
| 14 | x264 | master | Custom |
| 15 | FFmpeg | 7.1 | Custom |
| 16 | SDL2 | 2.30.0 | CMake |
| 17 | libexif | 0.6.25 | Autoconf |
| 18 | libebur128 | latest | CMake |
| 19 | dlfcn-win32 | latest | CMake |
| 20 | **MLT** | latest | CMake |

> **Note:** pcre2 is only built separately on Ubuntu. On Alpine it is available as a system package (`pcre2-dev`).


---

## Manual Build Steps (Alpine)

> These steps are for reference. For automated builds, use `build-all.sh` or `build-all-ubuntu.sh` instead.

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
# Use install-data + install-exec to skip fc-cache (cannot run on Linux)
make install-data install-exec
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

### 19. MLT
```bash
cd ~/tools/src
git clone https://github.com/mltframework/mlt.git mlt-win
cd mlt-win
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


---

## Known Issues

- `DMOD_QT6=OFF` — Qt6 cross compile is not supported
- `DMOD_GDK=OFF` — GDK/GTK cross compile has unresolved issues
- `DMOD_JACKRACK=OFF` — JACK audio is not available on Windows
- fontconfig uses `make install-exec` + `make install-data` instead of `make install` because `fc-cache.exe` cannot run on Linux
- On Ubuntu, pcre2 must be cross-compiled separately — it is not available as a MinGW system package unlike on Alpine
- MLT `lib/mlt` and `share/mlt` paths may need to be set manually via environment variables on Windows


---

## Running on Windows

MLT requires environment variables to find its modules and data files at runtime. Use `run_melt.ps1` instead of calling `melt.exe` directly.

### Setup

Extract the release zip. If `run_melt.ps1` is not included, create it manually — save the file below into the same folder as `melt.exe`:

```powershell
# run_melt.ps1
# PowerShell script to run melt.exe with the correct MLT environment

# $PSScriptRoot = folder where run_melt.ps1 is located (automatic, dynamic)
# Set MLT_HOME to the win-deps folder
$env:MLT_HOME = $PSScriptRoot

# Add bin and root to PATH so DLLs can be found
$env:PATH = "$env:MLT_HOME\bin;$env:MLT_HOME;$env:PATH"

# cd into the MLT folder so melt.exe can resolve share/lib relative paths
Set-Location $env:MLT_HOME

# Run melt.exe, forwarding all arguments passed to this script
echo "" | & "$env:MLT_HOME\melt.exe" $args
```

Then open PowerShell inside the extracted folder and run:

```powershell
.\run_melt.ps1 [melt arguments]
```

**Example:**

```powershell
# Show melt version
.\run_melt.ps1 --version

# Render a project
.\run_melt.ps1 project.mlt -consumer avformat:output.mp4
```

### What the script does

```powershell
$env:MLT_HOME = $PSScriptRoot                          # set root to script's folder
$env:PATH     = "$env:MLT_HOME\bin;$env:MLT_HOME;..."  # add DLL paths
Set-Location $env:MLT_HOME                             # cd into root so relative paths work
echo "" | & "$env:MLT_HOME\melt.exe" $args             # run melt.exe with your arguments
```

It sets `MLT_HOME`, adds `bin\` to PATH so all DLLs are found, and `cd`s into the folder so `lib\mlt` and `share\mlt` are resolved correctly relative to the working directory.

> **Note:** Jika PowerShell memblokir script dengan execution policy error, jalankan sekali:
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
> ```


---

## Pre-built Binaries

Don't want to build from source? Download pre-built binaries directly:

> **[Download pre-built binaries from Releases](https://github.com/friskipradana/mlt-windows-crosscompile/releases)**

Extract and run `melt.exe` from the extracted folder.

> ⚠️ **Alpha release** — Path configuration for `lib/mlt` and `share/mlt` may need to be set manually via environment variables. Not yet fully tested on all Windows environments.


---

## License

This repository is licensed under the GNU General Public License v3.0 (GPLv3).

This project contains build scripts used to compile MLT Framework and its dependencies.

MLT Framework itself is licensed under the LGPLv2.1.
See https://mltframework.org for details.