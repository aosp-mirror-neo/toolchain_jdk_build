#!/bin/bash

source $(dirname $0)/build-openjdk-common.sh

clang_dir=${TOP}/prebuilts/clang/host/darwin-x86/clang-r399163b
freetype=freetype-2.8

export PATH=${clang_dir}/bin:${PATH}

(
  cd ${OUT}
  tar jxf ${TOP}/toolchain/jdk/deps/src/${freetype}.tar.bz2
)

SYSROOT=$(xcrun --show-sdk-path)
GLOBAL_FLAGS=(
  -isysroot ${SYSROOT}
  --sysroot ${SYSROOT}
  -F ${SYSROOT}/System/Library/Frameworks/JavaVM.framework/Frameworks
  -Wno-conversion
  -Wno-deprecated-declarations
  -Wno-expansion-to-defined
  -Wno-format
  -Wno-implicit-function-declaration
  -Wno-incompatible-pointer-types
  -Wno-logical-op-parentheses
  -Wno-macro-redefined
  -Wno-missing-field-initializers
  -Wno-missing-method-return-type
  -Wno-parentheses
  -Wno-parentheses-equality
  -Wno-reserved-user-defined-literal
  -Wno-self-assign
  -Wno-shift-negative-value
  -Wno-sign-compare
  -Wno-sign-conversion
  -Wno-switch
  -Wno-tautological-compare
  -Wno-tautological-undefined-compare
  -Wno-unused-command-line-argument
  -Wno-unused-function
  -Wno-unused-parameter

  -Wno-deprecated-register
  -Wno-c++11-narrowing

  -Wno-undefined-var-template
)
GLOBAL_FLAGS=${GLOBAL_FLAGS[@]}

CC=clang
CXX=clang++

export MACOSX_DEPLOYMENT_TARGET=10.8

(
  cd ${OUT}/${freetype}
  bash configure \
    --with-png=no \
    --with-harfbuzz=no \
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

if [ "$JDK_VERSION" = "8u" ]; then
    extra_build_flags=COMPILER_WARNINGS_FATAL=false
fi

build_openjdk_images ${extra_build_flags}

# Rewrite absolute references to libfreetype.6.dylib to rpath-relative references
for lib in $(find ${OUT}/images/jdk ${OUT}/images/jre ${OUT}/images/jdk-bundle ${OUT}/images/jre-bundle \
    -name "libfontmanager.dylib"); do
  install_name_tool -change /usr/local/lib/libfreetype.6.dylib @rpath/libfreetype.dylib.6 $lib
done

dist_openjdk
