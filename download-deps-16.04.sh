#!/bin/bash -e

pkgs=$(echo \
  libwayland-dev \
  libwayland-client0 \
  libwayland-cursor0 \
)

cd $(dirname $0)/../deps

apt-get download $pkgs
(cd src && apt-get source --download-only $pkgs)

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
