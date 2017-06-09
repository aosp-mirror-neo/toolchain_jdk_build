#!/bin/bash -e

if [ -z $(docker images -q openjdk-android-build 2> /dev/null) ]; then
    echo "Missing openjdk-android-build image, run:"
    echo "docker build $(dirname $0) -t openjdk-android-build"
    exit 1
fi

if [ -z "${DIST_DIR}" ]; then
    echo "DIST_DIR must be set"
    exit 1
fi

mkdir -p ${DIST_DIR}
DIST=$(cd ${DIST_DIR} && pwd)

docker run \
    --rm \
    -v $PWD:/home/build/src:ro \
    -v ${DIST}:/home/build/dist \
    -t \
    -e USER_ID=$(id -u) \
    -e BUILD_NUMBER=${BUILD_NUMBER} \
    -e OUT_DIR=/home/build/out \
    -e DIST_DIR=/home/build/dist \
    -w /home/build/src \
    openjdk-android-build \
    toolchain/jdk/build/build-openjdk-linux.sh
