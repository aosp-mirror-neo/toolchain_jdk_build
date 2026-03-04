#!/bin/sh -e

# Downloads necessary dependencies to hermetically build openjdk against
# musl.  Expects to be run in a Alpine linux docker container.

case $(uname -m) in
  aarch64)
    arch=arm64
    ;;
  x86_64)
    arch=x86_64
    ;;
  *)
    echo "Unsupported arch $(uname -m)"
    exit 1
esac

pkgs=$(echo \
  alsa-lib \
  alsa-lib-dev \
  cups-dev  \
  cups-libs \
  fontconfig-dev \
  libx11 \
  libx11-dev \
  libxcb-dev \
  libxext \
  libxext-dev \
  libxi \
  libxi-dev \
  libxrandr-dev \
  libxrender \
  libxrender-dev \
  libxt-dev \
  libxtst \
  libxtst-dev \
  xorgproto
)

cd $(dirname $0)/../deps/linux_musl_${arch}

rm -f *.apk
rm -rf src

mkdir -p src

apk update

function package_with_version() {
  apk info -d $1 | awk 'NR == 1 {print $1}'
}

function package_origin() {
  tar xf $(package_with_version ${pkg}).apk -O .PKGINFO | awk '$1 ~ /origin/ { print $3 }'
}

aports_dir=$(mktemp -d)
git clone --depth 1 --branch v$(cat /etc/alpine-release) git://git.alpinelinux.org/aports ${aports_dir}

for pkg in ${pkgs}; do
  apk fetch ${pkg}
  origin=$(package_origin $pkg)
  abuild -F -C ${aports_dir}/main/${origin}/ -P $PWD srcpkg
done

rm -rf ${aports_dir}
