#!/bin/bash
#
# Builds JDK11, optionally creating distribution artifacts for it.
# Usage:
#   build_openjdk11-darwin.sh [-q] [-d <dist_dir>] build_dir
# The JDK is built in <build_dir>.
# With -d, creates the following artifacts in <dist_dir>:
#   jdk.zip              archive of the JDK distribution
#   jdk-debuginfo.zip    debug info files for JDK's shared libraries
#   configure.log
#   build.log
# Specify -q to suppress most of the output noise
#
# NOTE: make sure 'autoconf' is on the path.
#
set -eu
declare -r prog="${0##*/}"

function usage() {
  cat <<EOF
Usage:
    $prog [-q] [-d <dist_dir>] <build_dir>
JDK is built in <build_dir>.
With -d, creates the artifacts in <dist_dir>.
With -q, runs with minimum noise.
EOF
  exit 1
}

# Alas, Darwin does not have realpath.
realpath() {
    cd $1 && pwd
}

# Creates the directory if it does not exist and returns its absolute path
function make_target_dir() {
  mkdir -p "$1" && realpath "$1"
}

# Installs autoconf into specified directory. The second argument is working directory.
function install_autoconf() {
  local -r workdir=$(make_target_dir "$2")
  local -r installdir=$(make_target_dir "$1")
  tar -C "$workdir" -xzf toolchain/jdk/deps/src/autoconf-2.69.tar.gz
  (cd "$workdir"/autoconf-2.69 &&
     ./configure --prefix="$installdir" ${quiet:+--quiet} &&
     make ${quiet:+-s} install
  )
}

# Options
while getopts 'qd:' opt; do
  case $opt in
    d) dist_dir=$(make_target_dir $OPTARG) ;;
    q) quiet=t ;;
    *) usage ;;
  esac
done
shift $(($OPTIND-1))
(($#==1)) || usage

declare -r out_path=$(make_target_dir "$1")
declare -r sysroot=$(xcrun --show-sdk-path)
declare -r build_dir="$out_path/build"
declare -r top=$(realpath "$(dirname "$0")/../../..")
declare -r clang_bin="$top/prebuilts/clang/host/darwin-x86/clang-r399163b/bin"
declare -r autoconf_dir=$(make_target_dir "$out_path/autoconf")

# Darwin lacks autoconf, install it for this build.
install_autoconf "$autoconf_dir" "$out_path"

# Configure
mkdir -p "$build_dir"
[[ -n "${quiet:-}" ]] || set -x
# TODO(asmundak): JDK9 builds its own version of the freetype. Not sure why it is needed.
(cd "$build_dir" &&
   PATH="$autoconf_dir/bin":$PATH bash +x "$top/toolchain/jdk/jdk11/configure" \
     ${quiet:+--quiet} \
     --with-boot-jdk="$top/prebuilts/jdk/jdk9/darwin-x86" \
     --disable-full-docs \
     --disable-warnings-as-errors \
     --with-sysroot="$sysroot"\
     --with-freetype=bundled \
     --with-libpng=bundled \
     --with-native-debug-symbols=external \
     --with-stdc++lib=static \
     --with-toolchain-type=clang \
     --with-tools-dir="$clang_bin" \
     --with-version-pre= \
     --with-version-opt=${BUILD_NUMBER:-0} \
     --with-vendor-version-string=Android_PDK \
     --with-zlib=bundled \
     AR=llvm-ar NM=llvm-nm OBJDUMP=llvm-objdump STRIP=llvm-strip
)

# Make
declare -r make_log_level=${quiet:+warn}
make -C "$build_dir" LOG=${make_log_level:-debug} ${quiet:+-s} images
[[ -n "${dist_dir:-}" ]] || exit 0

# Dist
rm -rf "$dist_dir"/{jdk.zip,jdk-debuginfo.zip,build.log,configure.log}
# TODO(asmundak): JDK9 also created jdk-bundle.zip -- what is it for?
(cd "$build_dir/images/jdk" &&
  zip -9rDy${quiet:+q} "$dist_dir"/jdk.zip . -x 'demo/*' -x'man/*' -x'*.dSYM' &&
  zip -9rDy${quiet:+q} "$dist_dir"/jdk-debuginfo.zip . -i'*.dSYM/*'
)
cp "$build_dir"/build.log "$dist_dir"
cp "$build_dir"/configure-support/config.log "$dist_dir"/configure.log
