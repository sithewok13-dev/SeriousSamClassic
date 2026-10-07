#!/bin/bash
# Builds SDL2 and gl4es as static iOS (arm64) libraries into $1.
set -ex
DEPS="$1"
: "${IOS_MIN:=14.0}" "${SDL_TAG:=release-2.30.8}" "${GL4ES_SHA:=ec16bedd8819c475326f4f1a3063772c6d986e06}"
WORK="${RUNNER_TEMP:-/tmp}/ios-deps-src"
rm -rf "$WORK"; mkdir -p "$WORK" "$DEPS"
IOSFLAGS=(-G Ninja -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64
          -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN" -DCMAKE_BUILD_TYPE=Release)

# --- SDL2
git clone --depth 1 -b "$SDL_TAG" https://github.com/libsdl-org/SDL.git "$WORK/SDL"
cmake -S "$WORK/SDL" -B "$WORK/SDL/build" "${IOSFLAGS[@]}" \
  -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF -DSDL_HIDAPI=OFF \
  -DCMAKE_INSTALL_PREFIX="$DEPS"
cmake --build "$WORK/SDL/build"
cmake --install "$WORK/SDL/build"

# --- gl4es (desktop OpenGL 1.x on top of OpenGL ES 2)
git clone https://github.com/ptitSeb/gl4es.git "$WORK/gl4es"
git -C "$WORK/gl4es" checkout "$GL4ES_SHA"
cmake -S "$WORK/gl4es" -B "$WORK/gl4es/build" "${IOSFLAGS[@]}" \
  -DNOX11=ON -DNOEGL=ON -DSTATICLIB=ON -DNO_LOADER=ON -DNO_INIT_CONSTRUCTOR=ON -DDEFAULT_ES=2
cmake --build "$WORK/gl4es/build"
mkdir -p "$DEPS/gl4es/lib"
cp -R "$WORK/gl4es/include" "$DEPS/gl4es/"
find "$WORK/gl4es" -name "libGL.a" -exec cp {} "$DEPS/gl4es/lib/" \;
test -f "$DEPS/gl4es/lib/libGL.a"
test -f "$DEPS/lib/libSDL2.a"
ls -la "$DEPS/lib" "$DEPS/gl4es/lib"
