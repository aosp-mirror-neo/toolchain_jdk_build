#!/bin/bash -e

pkgs=$(
	echo \
		libasound2 \
		libasound2-dev \
		libcups2-dev \
		libcupsimage2-dev \
		libdbus-1-dev \
		libfontconfig1-dev \
		libfreetype6 \
		libfreetype6-dev \
		libpng-dev \
		libspeechd-dev \
		libspeechd2 \
		libwayland-bin \
		libwayland-client0 \
		libwayland-cursor0 \
		libwayland-dev \
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
		libxi-dev \
		libxkbcommon-dev \
		libxkbcommon-dev \
		libxkbcommon-x11-0 \
		libxkbcommon0 \
		libxrandr-dev \
		libxrender-dev \
		libxrender1 \
		libxt-dev \
		libxtst-dev \
		linux-libc-dev \
		wayland-protocols \
		x11proto-dev
)

cd $(dirname $0)/../deps

echo "Requested packages: $pkgs"

# Ubuntu 20.04 have too old version of wayland-protocols
# Directly download newer one separatelly
wget https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/wayland-protocols/1.45-1~ubuntu0.24.04.1/wayland-protocols_1.45.orig.tar.xz

apt-get download $pkgs
(mkdir -p src && cd src && apt-get source --download-only $pkgs)

function deb_to_license() {
	local data=$(ar t $1 | grep data.tar)
	local decompress
	if [ "${data}" = "data.tar.xz" ]; then
		decompress="-J"
	elif [ "${data}" = "data.tar.bz2" ]; then
		decompress="-j"
	elif [ "${data}" = "data.tar.gz" ]; then
		decompress="-z"
	elif [ "${data}" = "data.tar.zst" ]; then
		decompress="-I zstd"
	else
		echo "Unrecognized data file '${data}' in $1" >&2
		exit 1
	fi

	ar p $1 ${data} | tar x ${decompress} -O --wildcards "./usr/share/doc/*/copyright" 2>/dev/null || true
}

rm -f LICENSE LICENSE.tmp
for i in *.deb; do
	deb_to_license $i >LICENSE.tmp
	if [ -s LICENSE.tmp ]; then
		(
			echo $i
			printf '=%.0s' $(seq 1 ${#i})
			echo
			cat LICENSE.tmp
			echo
		) >>LICENSE
	fi
	rm -f LICENSE.tmp
done
