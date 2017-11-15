#!/bin/bash

source $(dirname $0)/build-openjdk-common.sh

SYSROOT=${OUT}/sysroot
gcc_dir=${TOP}/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.15-4.8/bin

function unpack_deb() {
  mkdir -p ${OUT}/sysroot
  (
    cd ${OUT}/sysroot
    local data=$(${gcc_dir}/x86_64-linux-ar t $1 | grep data.tar)
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
    ${gcc_dir}/x86_64-linux-ar p $1 ${data} | tar ${tar_args}
  )
}

export PATH=${gcc_dir}:${PATH} \

(
  cd ${OUT}
  for i in ${TOP}/toolchain/jdk/deps/*.deb; do
    unpack_deb $i
  done
)

GLOBAL_FLAGS="--sysroot=${SYSROOT}"
CC=x86_64-linux-gcc
CXX=x86_64-linux-g++


configure_openjdk \
  --x-libraries=${SYSROOT}/usr/lib/x86_64-linux-gnu/ \
  --x-includes=${SYSROOT}/usr/include \
  --with-cups-include=${SYSROOT}/usr/include \
  --with-freetype-lib=${SYSROOT}/usr/lib/x86_64-linux-gnu/ \
  --with-freetype-include=${SYSROOT}/usr/include/freetype2 \
  --with-alsa-lib=${SYSROOT}/usr/lib/x86_64-linux-gnu/ \
  --with-alsa-include=${SYSROOT}/usr/include \
  --with-stdc++lib=static \
  --disable-freetype-bundling \
  AR=x86_64-linux-ar \
  NM=x86_64-linux-nm \
  OBJCOPY=x86_64-linux-objcopy \
  OBJDUMP=x86_64-linux-objdump \
  READELF=x86_64-linux-readelf \
  STRIP=x86_64-linux-strip \
  BUILD_AR="$(which x86_64-linux-ar)" \
  BUILD_NM="$(which x86_64-linux-nm)" \
  BUILD_OBJCOPY="$(which x86_64-linux-objcopy)" \
  BUILD_STRIP="$(which x86_64-linux-strip)" \

build_openjdk_images

dist_openjdk
