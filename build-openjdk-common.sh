set -e
set -x

if [ "$1" = "--version=9" ]; then
  JDK_SRC=toolchain/jdk
  JDK_VERSION=9
  JDK_MILESTONE=android
  JDK_UPDATE_VERSION=181
  JDK_USER_RELEASE_SUFFIX=${BUILD_NUMBER}
else
  JDK_SRC=external/jetbrains
  jdk_build_txt=external/jetbrains/jdk8u_jdk/build.txt
  JDK_VERSION="$(sed 's/u.*$//' ${jdk_build_txt})u"
  JDK_MILESTONE=release
  JDK_UPDATE_VERSION="$(sed 's/^.*u//;s/-b.*$//' ${jdk_build_txt})"
  JDK_USER_RELEASE_SUFFIX="$(sed 's/^.*-b//;s/\..*$//' ${jdk_build_txt})"
  JDK_BUILD_NUMBER="b$(sed 's/^.*\.//' ${jdk_build_txt})-${BUILD_NUMBER}"
fi

if [ -z "${OUT_DIR}" ]; then
  echo "OUT_DIR must be set"
  exit 1
fi

mkdir -p ${OUT_DIR}
OUT=$(cd ${OUT_DIR} && pwd)
TOP=$(cd $(dirname $0)/../../.. && pwd)

case $(uname) in
  Linux)
    PREBUILT_DIR=linux-x86
    TRIPLE=x86_64-linux-gnu
    JAVA_PREBUILT_SUBDIR=linux-x86
    OPENJDK_IMAGES_SUBDIR=linux-x86_64-normal-server-release
    ;;
  Darwin)
    PREBUILT_DIR=darwin-x86
    TRIPLE=x86_64-apple-darwin
    JAVA_PREBUILT_SUBDIR=darwin-x86
    OPENJDK_IMAGES_SUBDIR=macosx-x86_64-normal-server-release
    ;;
  *) echo "unknown OS:" $(uname) && exit 1;;
esac

BUILD_TOOLS=${TOP}/prebuilts/build-tools/${PREBUILT_DIR}/bin

ln -sf ${TOP}/${JDK_SRC}/jdk${JDK_VERSION}/* ${OUT}/
for i in $(cd ${TOP}/${JDK_SRC}; ls -d jdk${JDK_VERSION}_*); do
  rm -f ${OUT}/${i/jdk${JDK_VERSION}_/}
  ln -sf ${TOP}/${JDK_SRC}/${i} ${OUT}/${i/jdk${JDK_VERSION}_/}
done

function configure_openjdk() {
  if [ "$JDK_VERSION" = "9" ]; then
    configure_openjdk9 "$@"
  else
    configure_openjdk8 "$@"
  fi
}

function configure_openjdk8() {
  GLOBAL_FLAGS_IN_CC=" ${GLOBAL_FLAGS}"

  configure_openjdk_common \
    --host=$TRIPLE \
    --disable-zip-debug-info \
    --with-milestone=${JDK_MILESTONE} \
    --with-update-version=${JDK_UPDATE_VERSION} \
    --with-build-number=${JDK_BUILD_NUMBER} \
    --with-user-release-suffix=${JDK_USER_RELEASE_SUFFIX} \
    "$@"
}

function configure_openjdk9() {
  GLOBAL_FLAGS_IN_CC=""

  configure_openjdk_common \
    --openjdk-target=$TRIPLE \
    --with-native-debug-symbols=external \
    --with-version-pre="" \
    --with-version-build=${JDK_UPDATE_VERSION} \
    --with-version-opt=android${BUILD_NUMBER} \
    --with-sysroot=${SYSROOT} \
    BUILD_SYSROOT_CFLAGS="${GLOBAL_FLAGS}" \
    BUILD_SYSROOT_LDFLAGS="${GLOBAL_FLAGS}" \
    "$@"
}

function configure_openjdk_common() {
  (
    cd $OUT
    bash configure \
      --with-boot-jdk=${TOP}/prebuilts/jdk/jdk8/${JAVA_PREBUILT_SUBDIR} \
      --with-extra-cflags="$GLOBAL_FLAGS" \
      --with-extra-cxxflags="$GLOBAL_FLAGS" \
      LDFLAGS="${GLOBAL_FLAGS}" \
      CFLAGS="${GLOBAL_FLAGS}" \
      CPPFLAGS="${GLOBAL_FLAGS}" \
      CXXFLAGS="${GLOBAL_FLAGS}" \
      X_CFLAGS="${GLOBAL_FLAGS}" \
      CCXXFLAGS_JDK="${GLOBAL_FLAGS}" \
      LDFLAGS_JDK="${GLOBAL_FLAGS}" \
      CC="${CC}" \
      CXX="${CXX}" \
      LD="${CC}" \
      BUILD_CC="$(which ${CC})${GLOBAL_FLAGS_IN_CC}" \
      BUILD_CXX="$(which ${CXX})${GLOBAL_FLAGS_IN_CC}" \
      BUILD_LD="$(which ${CC})${GLOBAL_FLAGS_IN_CC}" \
      ZIP="/usr/bin/zip -X" \
      "$@"
  )
}

function soong_zip() {
  ${BUILD_TOOLS}/soong_zip -o $1 -C $2 -l <(find $2 | sort)
}

function sanitize_zips() {
  for i in $(find ${1} -type f \( -name "*.jar" -o -name "*.zip" -o -name "*.sym" \) ); do
    ${BUILD_TOOLS}/zip2zip -j -t -i $i -o $i.tmp
    mv -f $i.tmp $i
  done
}

function move_debuginfo() {
  for i in $(find ${1} -name "*.debuginfo" -o -name "*.dSYM"); do
    mkdir -p $(dirname ${i/${1}/${2}})
    mv ${i} ${i/${1}/${2}}
  done
}

function delete_debuginfo() {
    rm -rf $(find ${1} -name "*.debuginfo" -o -name "*.dSYM")
}


function build_openjdk_images() {
  (
    cd $OUT

    if [ "${JDK_VERSION}" = "9" ]; then
      verbose="LOG=debug"
    else
      verbose="VERBOSE="
    fi

    make images ${verbose} ${@}
    rm -rf images/
    mkdir images
    cp -r build/${OPENJDK_IMAGES_SUBDIR}/images/* images/

    if [ -d images/j2sdk-image ]; then
      mv images/j2sdk-image images/jdk
      mv images/j2re-image images/jre
    fi

    if [ -d images/j2sdk-bundle ]; then
      mv images/j2sdk-bundle images/jdk-bundle
      mv images/j2re-bundle images/jre-bundle
    fi

    rm -rf images/jdk/demo/
    rm -rf images/jdk/samples/
    rm -rf images/jdk/man/
    if [ -d images/jdk-bundle ]; then
      rm -rf images/jdk-bundle/*/Contents/Home/demo/
      rm -rf images/jdk-bundle/*/Contents/Home/sample/
      rm -rf images/jdk-bundle/*/Contents/Home/man/
    fi

    move_debuginfo images/jdk images/jdk-debuginfo
    delete_debuginfo images/jre
    if [ -d images/jdk-bundle ]; then
      delete_debuginfo images/jdk-bundle
      delete_debuginfo images/jre-bundle
    fi
  )

  sanitize_zips $OUT/images
}

function dist_openjdk() {
  if [ -n "${DIST_DIR}" ]; then
    mkdir -p ${DIST_DIR}
    DIST=$(cd ${DIST_DIR} && pwd)
    soong_zip ${DIST}/jre.zip ${OUT}/images/jre
    soong_zip ${DIST}/jdk.zip ${OUT}/images/jdk
    soong_zip ${DIST}/jdk-debuginfo.zip ${OUT}/images/jdk-debuginfo
    if [ -d "${OUT}/images/jre-bundle" ]; then
      soong_zip ${DIST}/jre-bundle.zip ${OUT}/images/jre-bundle
      soong_zip ${DIST}/jdk-bundle.zip ${OUT}/images/jdk-bundle
    fi
    cp -f ${OUT}/build/${OPENJDK_IMAGES_SUBDIR}/config*.log ${DIST_DIR}/
  fi
}
