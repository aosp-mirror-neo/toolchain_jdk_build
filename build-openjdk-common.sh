set -e
set -x

JDK_UPDATE_VERSION=152
JDK_BUILD_NUMBER=1

if [ -z "${OUT_DIR}" ]; then
  echo "OUT_DIR must be set"
  exit 1
fi

mkdir -p ${OUT_DIR}
OUT=$(cd ${OUT_DIR} && pwd)
TOP=$(cd $(dirname $0)/../../.. && pwd)
JDK_SRC=${TOP}/external/jetbrains

case $(uname) in
  Linux)
    PREBUILT_DIR=linux-x86
    TRIPLE=x86_64-linux-gnu
    JAVA_PREBUILT_SUBDIR=linux
    OPENJDK_IMAGES_SUBDIR=linux-x86_64-normal-server-release
    ;;
  Darwin)
    PREBUILT_DIR=darwin-x86
    TRIPLE=x86_64-apple-darwin
    JAVA_PREBUILT_SUBDIR=mac/Contents/Home
    OPENJDK_IMAGES_SUBDIR=macosx-x86_64-normal-server-release
    ;;
  *) echo "unknown OS:" $(uname) && exit 1;;
esac

BUILD_TOOLS=${TOP}/prebuilts/build-tools/${PREBUILT_DIR}/bin

ln -sf ${JDK_SRC}/jdk8u/* ${OUT}/
for i in $(cd ${JDK_SRC}; ls -d jdk8u_*); do
  rm -f ${OUT}/${i/jdk8u_/}
  ln -sf ${JDK_SRC}/${i} ${OUT}/${i/jdk8u_/}
done

function configure_openjdk() {
  (
    cd $OUT
    bash configure \
      --host=$TRIPLE \
      --disable-zip-debug-info \
      --with-boot-jdk=${TOP}/prebuilts/studio/jdk/${JAVA_PREBUILT_SUBDIR} \
      --with-milestone=android \
      --with-update-version=${JDK_UPDATE_VERSION} \
      --with-build-number=${JDK_BUILD_NUMBER} \
      --with-user-release-suffix=${BUILD_NUMBER} \
      --with-extra-cflags="$GLOBAL_FLAGS" \
      --with-extra-cxxflags="$GLOBAL_FLAGS" \
      LDFLAGS="${GLOBAL_FLAGS}" \
      CFLAGS="${GLOBAL_FLAGS}" \
      CPPFLAGS="${GLOBAL_FLAGS}" \
      CXXFLAGS="${GLOBAL_FLAGS}" \
      X_CFLAGS="${GLOBAL_FLAGS}" \
      CCXXFLAGS_JDK="${GLOBAL_FLAGS}" \
      LDFLAGS_JDK="${GLOBAL_FLAGS}" \
      CC="${CC} ${GLOBAL_FLAGS}" \
      CXX="${CXX} ${GLOBAL_FLAGS}" \
      LD="${CC} ${GLOBAL_FLAGS}" \
      BUILD_CC="$(which ${CC}) ${GLOBAL_FLAGS}" \
      BUILD_CXX="$(which ${CXX}) ${GLOBAL_FLAGS}" \
      BUILD_LD="$(which ${CC}) ${GLOBAL_FLAGS}" \
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
  for i in $(find ${1} -name "*.debuginfo"); do
    mkdir -p $(dirname ${i/${1}/${2}})
    mv ${i} ${i/${1}/${2}}
  done
}

function build_openjdk_images() {
  (
    cd $OUT
    make images VERBOSE= ${@}
    rm -rf images/
    mkdir images
    cp -r build/${OPENJDK_IMAGES_SUBDIR}/images/* images/
    rm -rf images/j2sdk-image/demo/
    rm -rf images/j2sdk-image/sample/
    rm -rf images/j2sdk-image/man/
    if [ -d images/j2sdk-bundle ]; then
      rm -rf images/j2sdk-bundle/*/Contents/Home/demo/
      rm -rf images/j2sdk-bundle/*/Contents/Home/sample/
      rm -rf images/j2sdk-bundle/*/Contents/Home/man/
    fi

    move_debuginfo images/j2sdk-image images/j2sdk-image-debuginfo
    rm $(find images/j2re-image -name "*.debuginfo")
  )

  sanitize_zips $OUT/images

  if [ -n "${DIST_DIR}" ]; then
    mkdir -p ${DIST_DIR}
    DIST=$(cd ${DIST_DIR} && pwd)
    soong_zip ${DIST}/jre.zip ${OUT}/images/j2re-image
    soong_zip ${DIST}/jdk.zip ${OUT}/images/j2sdk-image
    soong_zip ${DIST}/jdk-debuginfo.zip ${OUT}/images/j2sdk-image-debuginfo
    if [ -d "${OUT}/images/j2re-bundle" ]; then
      soong_zip ${DIST}/jre-bundle.zip ${OUT}/images/j2re-bundle
      soong_zip ${DIST}/jdk-bundle.zip ${OUT}/images/j2sdk-bundle
    fi
    cp -f ${OUT}/build/${OPENJDK_IMAGES_SUBDIR}/config.* ${DIST_DIR}/
  fi
}
