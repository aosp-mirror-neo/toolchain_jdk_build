#!/bin/bash

source $(dirname $0)/build-openjdk-common.sh

sdk_version=$(xcrun --show-sdk-version)
if [ "${sdk_version}" != "10.9" -a "${sdk_version}" != "10.10" ]; then
    echo "Xcode sdk version 10.9 or 10.10 is required"
    exit 1
fi
sysroot=$(xcrun --show-sdk-path)
clang_dir=${TOP}/prebuilts/clang/host/darwin-x86/clang-stable
freetype=freetype-2.8

export PATH=${clang_dir}/bin:${PATH}

(
  cd ${OUT}
  tar jxf ${TOP}/toolchain/jdk/deps/src/${freetype}.tar.bz2
)

GLOBAL_FLAGS="-isysroot ${sysroot}"
CC=clang
CXX=clang++

export MACOSX_DEPLOYMENT_TARGET=10.8

(
  cd ${OUT}/${freetype}
  bash configure \
    CC=clang \
    CC_BUILD=clang \
    LD=clang \
    CFLAGS="${GLOBAL_FLAGS}" \
  && make -j8 CCexe_CFLAGS="${GLOBAL_FLAGS}"
  mkdir -p lib
  cp objs/.libs/libfreetype.dylib lib/
)

configure_openjdk \
  --with-freetype=${OUT}/${freetype}

build_openjdk_images COMPILER_WARNINGS_FATAL=false
