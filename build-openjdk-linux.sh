#!/bin/bash

set -e

source $(dirname $0)/build-openjdk-common.sh

sysroot=${OUT}/sysroot
tools_dir=${TOP}/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.15-4.8/bin

function unpack_deb() {
  mkdir -p ${OUT}/sysroot
  (
    cd ${OUT}/sysroot
    local data=$(${tools_dir}/x86_64-linux-ar t $1 | grep data.tar)
    local tar_args
    if [ "${data}" = "data.tar.xz" ]; then
      tar_args="Jx"
    elif [ "${data}" = "data.tar.bz2" ]; then
      tar_args="jx"
    elif [ "${data}" = "data.tar.gz" ]; then
      tar_args="zx"
    else
      echo "Unrecognized data file '${data}' in $1" && false
    fi
    echo "Unpacking $1"
    ${tools_dir}/x86_64-linux-ar p $1 ${data} | tar ${tar_args}
  )
}

(
  cd ${OUT}
  for i in ${TOP}/toolchain/jdk/deps/*.deb; do
    unpack_deb $i
  done

  PATH=${tools_dir}:${PATH} \
    bash configure \
    --host=x86_64-linux-gnu \
    --with-boot-jdk=${TOP}/prebuilts/studio/jdk/linux/ \
    --x-libraries=${sysroot}/usr/lib/x86_64-linux-gnu/ \
    --x-includes=${sysroot}/usr/include \
    --with-cups-include=${sysroot}/usr/include \
    --with-freetype-lib=${sysroot}/usr/lib/x86_64-linux-gnu/ \
    --with-freetype-include=${sysroot}/usr/include/freetype2 \
    --with-alsa-lib=${sysroot}/usr/lib/x86_64-linux-gnu/ \
    --with-alsa-include=${sysroot}/usr/include \
    --disable-zip-debug-info \
    --with-stdc++lib=static \
    --with-milestone=android \
    --with-update-version=${JDK_UPDATE_VERSION} \
    --with-build-number=${JDK_BUILD_NUMBER} \
    --with-user-release-suffix=${BUILD_NUMBER} \
    --with-extra-cflags="--sysroot=${sysroot}" \
    --with-extra-cxxflags="--sysroot=${sysroot}" \
    LDFLAGS="--sysroot=${sysroot}" \
    CFLAGS="--sysroot=${sysroot}" \
    CPPFLAGS="--sysroot=${sysroot}" \
    CXXFLAGS="--sysroot=${sysroot}" \
    X_CFLAGS="--sysroot=${sysroot}" \
    CCXXFLAGS_JDK="--sysroot=${sysroot}" \
    LDFLAGS_JDK="--sysroot=${sysroot}" \
    CC=x86_64-linux-gcc \
    CXX=x86_64-linux-g++ \
    LD=x86_64-linux-gcc \
    BUILD_CC=${tools_dir}/x86_64-linux-gcc \
    BUILD_CXX=${tools_dir}/x86_64-linux-g++ \
    BUILD_LD=${tools_dir}/x86_64-linux-gcc \
    AR=x86_64-linux-ar \
    NM=x86_64-linux-nm \
    OBJCOPY=x86_64-linux-objcopy \
    OBJDUMP=x86_64-linux-objdump \
    READELF=x86_64-linux-readelf \
    STRIP=x86_64-linux-strip \
    ZIP="/usr/bin/zip -X" \
  && make images VERBOSE=
)

build=${OUT}/build/linux-x86_64-normal-server-release
images=${build}/images

sanitize_zips ${images}

if [ -n "${DIST_DIR}" ]; then
    mkdir -p ${DIST_DIR}
    DIST=$(cd ${DIST_DIR} && pwd)
    soong_zip ${DIST}/jre.zip ${images}/j2re-image
    soong_zip ${DIST}/jdk.zip ${images}/j2sdk-image
    cp -f ${build}/config.* ${DIST_DIR}/
fi


