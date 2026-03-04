#!/bin/bash -e

cd $(dirname $0)/../../..

if [ -z $(docker images -q openjdk-android-deps-musl 2> /dev/null) ]; then
    echo "Missing openjdk-android-build-musl image, run:"
    echo "cd $(dirname $0) && docker build . -f Dockerfile.musl_deps -t openjdk-android-deps-musl"
    exit 1
fi

docker run \
    --rm \
    -v $(cd toolchain/jdk/build; pwd):/home/build/build:ro \
    -v $(cd toolchain/jdk/deps; pwd):/home/build/deps \
    -t \
    -e USER_ID=$(id -u) \
    -w /home/build/build \
    openjdk-android-deps-musl \
    "./download-deps-musl.sh"
