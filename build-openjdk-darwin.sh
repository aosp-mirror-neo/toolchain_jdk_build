#!/bin/bash

set -e

source $(dirname $0)/build-openjdk-common.sh

freetype=freetype-2.8
clang_dir=${TOP}/prebuilts/clang/host/darwin-x86/clang-stable
sdk_version=$(xcrun --show-sdk-version)
if [ "${sdk_version}" != "10.9" -a "${sdk_version}" != "10.10" ]; then
    echo "Xcode sdk version 10.9 or 10.10 is required"
    exit 1
fi
sysroot=$(xcrun --show-sdk-path)

export PATH=${clang_dir}/bin:${PATH}

(
  cd ${OUT}
  tar jxf ${TOP}/toolchain/jdk/deps/src/${freetype}.tar.bz2
  (
    cd ${freetype}
    bash configure \
      CC=clang \
      CC_BUILD=clang \
      LD=clang \
      CFLAGS="-isysroot ${sysroot}" \
    && make -j8 CCexe_CFLAGS="-isysroot ${sysroot}"
    mkdir -p lib
    cp objs/.libs/libfreetype.dylib lib/
  )

  export MACOSX_DEPLOYMENT_TARGET=10.8
  bash configure \
    --host=x86_64-apple-darwin \
    --with-boot-jdk=${TOP}/prebuilts/studio/jdk/mac/Contents/Home \
    --with-milestone=android \
    --with-update-version=${JDK_UPDATE_VERSION} \
    --with-build-number=${JDK_BUILD_NUMBER} \
    --with-user-release-suffix=${BUILD_NUMBER} \
    --with-freetype=${OUT}/${freetype} \
    --with-extra-cflags="-isysroot ${sysroot}" \
    --with-extra-cxxflags="-isysroot ${sysroot}" \
    LDFLAGS="-isysroot ${sysroot}" \
    CFLAGS="-isysroot ${sysroot}" \
    CPPFLAGS="-isysroot ${sysroot}" \
    CXXFLAGS="-isysroot ${sysroot}" \
    X_CFLAGS="-isysroot ${sysroot}" \
    CCXXFLAGS_JDK="-isysroot ${sysroot}" \
    LDFLAGS_JDK="-isysroot ${sysroot}" \
    CC="clang -isysroot ${sysroot}" \
    CXX="clang++ -isysroot ${sysroot}" \
    LD="clang -isysroot ${sysroot}" \
    BUILD_CC="${clang_dir}/bin/clang -isysroot ${sysroot}" \
    BUILD_CXX="${clang_dir}/bin/clang++ -isysroot ${sysroot}" \
    BUILD_LD="${clang_dir}/bin/clang -isysroot ${sysroot}" \
    ZIP="/usr/bin/zip -X" \
  && make images VERBOSE= COMPILER_WARNINGS_FATAL=false
)

build=${OUT}/build/macosx-x86_64-normal-server-release
images=${build}/images

sanitize_zips ${images}

if [ -n "${DIST_DIR}" ]; then
    mkdir -p ${DIST_DIR}
    DIST=$(cd ${DIST_DIR} && pwd)
    soong_zip ${DIST}/jre.zip ${images}/j2re-image
    soong_zip ${DIST}/jdk.zip ${images}/j2sdk-image
    soong_zip ${DIST}/jre-bundle.zip ${images}/j2re-bundle
    soong_zip ${DIST}/jdk-bundle.zip ${images}/j2sdk-bundle
    cp -f ${build}/config.* ${DIST_DIR}/
fi
