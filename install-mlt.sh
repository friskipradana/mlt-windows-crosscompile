cd /home/riky/tools/src/mlt-win/build
rm -rf *

cmake .. \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
  -DCMAKE_INSTALL_PREFIX=/home/riky/tools/win-deps \
  -DCMAKE_PREFIX_PATH=/home/riky/tools/win-deps \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXE_LINKER_FLAGS="-L/home/riky/tools/win-deps/lib" \
  -DCMAKE_SHARED_LINKER_FLAGS="-L/home/riky/tools/win-deps/lib" \
  -DCMAKE_C_FLAGS="-I/home/riky/tools/win-deps/include" \
  -DCMAKE_CXX_FLAGS="-I/home/riky/tools/win-deps/include" \
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

make -j$(nproc)
make install
