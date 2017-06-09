#!/bin/bash

set -e

source $(dirname $0)/build-openjdk-common.sh

sysroot=${OUT}/sysroot
tools_dir=${TOP}/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.15-4.8/bin
freetype=freetype-2.8

(
  cd ${OUT}
  tar jxf ${TOP}/toolchain/jdk/deps/src/${freetype}.tar.bz2
  (
    cd ${freetype}
    ./configure
    make -j8
    mkdir -p lib
    cp objs/.libs/libfreetype.dylib lib/
  )

  export MACOSX_DEPLOYMENT_TARGET=10.8
  bash configure \
    --with-boot-jdk=${TOP}/prebuilts/studio/jdk/mac/Contents/Home \
    --with-milestone=android \
    --with-update-version=${JDK_UPDATE_VERSION} \
    --with-build-number=${JDK_BUILD_NUMBER} \
    --with-user-release-suffix=${BUILD_NUMBER} \
    --with-freetype=${OUT}/${freetype} \
  && make images VERBOSE= COMPILER_WARNINGS_FATAL=false
)

build=${OUT}/build/macosx-x86_64-normal-server-release
images=${build}/images
for i in $(find ${images} -type f \( -name "*.jar" -o -name "*.zip" -o -name "*.sym" \) ); do
    ${TOP}/prebuilts/build-tools/darwin-x86/bin/ziptime $i
done

if [ -n "${DIST_DIR}" ]; then
    mkdir -p ${DIST_DIR}
    DIST=$(cd ${DIST_DIR} && pwd)
    (cd ${images}/j2re-image && zip -X -r ${DIST}/jre.zip *)
    (cd ${images}/j2sdk-image && zip -X -r ${DIST}/jdk.zip *)
    (cd ${images}/j2re-bundle && zip -X -r ${DIST}/jre-bundle.zip *)
    (cd ${images}/j2sdk-bundle && zip -X -r ${DIST}/jdk-bundle.zip *)
    for i in ${DIST_DIR}/*.zip; do
        ${TOP}/prebuilts/build-tools/darwin-x86/bin/ziptime $i
    done
    cp -f ${build}/config.* ${DIST_DIR}/
fi
