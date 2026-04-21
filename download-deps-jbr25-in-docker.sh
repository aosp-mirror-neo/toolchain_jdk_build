#!/bin/bash -e

# References:
#   OpenJDK build intructions : https://github.com/openjdk/jdk/blob/master/doc/building.md
#   JBR build intructions: https://github.com/JetBrains/JetBrainsRuntime/tree/jbr25
#   Android Studio system requirements: https://developer.android.com/studio/install
#   libraries versions in Ununtu: https://distrowatch.com/table.php?distribution=ubuntu

# Android Studio should works with glibc 2.31, at the same time it is prefered to use latest wayland version (as it is under active development)
# Use 20.04 as a base because of glibc

top=$(realpath "$(dirname "$0")/../../..")
target_dir=$top/toolchain/jdk/deps/jbr25/linux_x64
rm -rf $target_dir && mkdir -p $target_dir

echo "Building Docker image"
(
	cd $top/toolchain/jdk/build
	docker build . -f Dockerfile.jbr25_deps -t jbr25-deps-x64
)

echo "Downloading necessary dependencies to hermetically build JBR25"
(
	cd $top
	docker run \
		--rm \
		-v $top/toolchain/jdk/build:/home/build/build:ro \
		-v $target_dir:/home/build/deps \
		-t \
		-e USER_ID=$(id -u) \
		-w /home/build/build \
		jbr25-deps-x64 \
		"./download-deps-jbr25-x64.sh"
)

echo "Downloading dependencies done."
