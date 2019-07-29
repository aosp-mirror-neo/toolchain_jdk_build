#!/bin/bash -e

pkgs=$(echo \
  libasound2 \
  libasound2-dev \
  libc6 \
  libc6-dev \
  libcups2 \
  libcups2-dev \
  libfontconfig1-dev \
  libfreetype6 \
  libfreetype6-dev \
  libgcc-4.8-dev \
  libice-dev \
  libstdc++6 \
  libstdc++-4.8-dev \
  libpng12-0 \
  libpng12-dev \
  libsm-dev \
  libx11-6 \
  libx11-dev \
  libxau-dev \
  libxau6 \
  libxcb1 \
  libxcb1-dev \
  libxdmcp-dev \
  libxdmcp6 \
  libxext-dev \
  libxext6 \
  libxfixes-dev \
  libxfixes3 \
  libxi-dev \
  libxi6 \
  libxrender-dev \
  libxrender1 \
  libxt-dev \
  libxt6 \
  libxtst-dev \
  libxtst6 \
  linux-libc-dev \
  x11proto-core-dev \
  x11proto-fixes-dev \
  x11proto-input-dev \
  x11proto-kb-dev \
  x11proto-record-dev \
  x11proto-render-dev \
  x11proto-xext-dev \
  zlib1g \
  zlib1g-dev \
)

cd $(dirname $0)/../deps

apt download $pkgs
mkdir -p src
(cd src && apt source --download-only $pkgs)
(cd src && curl --location -O http://download.savannah.gnu.org/releases/freetype/freetype-2.8.tar.bz2)

function deb_to_license() {
  local data=$(ar t $1 | grep data.tar)
  local decompress
  if [ "${data}" = "data.tar.xz" ]; then
    decompress="-J"
  elif [ "${data}" = "data.tar.bz2" ]; then
    decompress="-j"
  elif [ "${data}" = "data.tar.gz" ]; then
    decompress="-z"
  else
    echo "Unrecognized data file '${data}' in $1" >&2
    exit 1
  fi

  ar p $1 ${data} | tar x ${decompress} -O --wildcards "./usr/share/doc/*/copyright" 2>/dev/null || true
}

rm -f LICENSE LICENSE.tmp
for i in *.deb; do
  deb_to_license $i > LICENSE.tmp
  if [ -s LICENSE.tmp ]; then
    (
      echo $i
      printf '=%.0s' $(seq 1 ${#i})
      echo
      cat LICENSE.tmp
      echo
    ) >> LICENSE
  fi
  rm -f LICENSE.tmp
done
