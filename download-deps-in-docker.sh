#!/bin/bash -e

cd $(dirname $0)/../../..

if [ -z $(docker images -q openjdk-android-deps 2> /dev/null) ]; then
    echo "Missing openjdk-android-build image, run:"
    echo "docker build $(dirname $0) -t openjdk-android-build"
    echo "docker build $(dirname $0) -f Dockerfile.deps -t openjdk-android-deps"
    exit 1
fi

docker run \
    --rm \
    -v $(cd toolchain/jdk/build; pwd):/home/build/build:ro \
    -v $(cd toolchain/jdk/deps; pwd):/home/build/deps \
    -t \
    -e USER_ID=$(id -u) \
    -w /home/build/build \
    openjdk-android-deps \
    "./download-deps.sh"
