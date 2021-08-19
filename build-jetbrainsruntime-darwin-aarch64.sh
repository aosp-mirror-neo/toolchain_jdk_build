#!/bin/bash
#
# Builds JDK11 for aarch64, optionally creating distribution artifacts for it.
# Usage:
#   build-jetbrainsruntime-darwin.sh [-q] [-d <dist_dir>] [-o <out_dir>] -b <build_number>
# The JDK is built in OUT_DIR (or "out" if unset).
# If DIST_DIR is set, the following artifacts are created there:
#   jdk.zip              archive of the JDK distribution
#   jdk-runtime.zip
#   jdk-debuginfo.zip    .debuginfo files for JDK's shared libraries
#   configure.log
#   build.log
# Specify -q to suppress most of the output noise
# Use -f to override location of JavaNativeFundation framework. By default one from Xcode would be used

set -eu

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
  tar -C "$workdir" -xzf "$top/toolchain/jdk/deps/src/autoconf-2.69.tar.gz"
  (cd "$workdir"/autoconf-2.69 &&
     ./configure --prefix="$installdir" ${quiet:+--quiet} &&
     make ${quiet:+-s} install
  )
}

# Converts version string to comparable number `12.3` -> 012003000000. Works for at most 4 fields
function ver { printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' '); }

function usage() {
  declare -r prog="${0##*/}"
  cat <<EOF
Usage:
    $prog [-q] [-d <dist_dir>] [-o <out_dit>] [-f <jnf_dir>] -b <build_number>
The JDK is built in <out_dir> (or "out" if unset).
If <dist_dir> is set, artifacts are created there.
Specify JBR build number with <build_number>
With -q, runs with minimum noise.
EOF
  exit 1
}

while getopts 'qb:d:o:' opt; do
  case $opt in
    b) build_number=$OPTARG ;;
    o) out_dir_option=$OPTARG;;
    d) dist_dir=$(make_target_dir $OPTARG) ;;
    q) quiet=t ;;
    *) usage ;;
  esac
done
shift $(($OPTIND-1))
(($#==0)) || usage

if [ -z "${out_dir_option:-}" ]; then
    out_dir_option="out"
fi

if [ -z "${build_number:-}" ]; then
    usage
fi

declare -r sdk_version=$(xcrun --show-sdk-version)
[ $(ver $sdk_version) -ge $(ver 11.1) ] ||
    {
        echo "Xcode sdk version 11.1 or later is required (Xcode 12.3 or later)"
        echo "selected Xcode version: $sdk_version"
        echo "selected Xcode path: $(xcrun --show-sdk-path)"
        exit 1
    }

declare -r out_path=$(make_target_dir "${out_dir_option}")
declare -r sysroot=$(xcrun --show-sdk-path)
declare -r build_dir="$out_path/build"
declare -r top=$(realpath "$(dirname "$0")/../../..")
declare -r autoconf_dir=$(make_target_dir "$out_path/autoconf")
declare -r boot_jdk="$top/prebuilts/jdk/studio/jdk11/mac/Contents/Home"
declare -r boot_jdk_version=$($boot_jdk/bin/java -version 2>&1 | head -1 | cut -d'"' -f2)


if [ $(ver $boot_jdk_version) -ge $(ver 12) ] || [ $(ver $boot_jdk_version) -lt $(ver 10) ]; then
    echo "Boot JDK version must be 10 or 11"
    exit 1
fi

#TODO(June 2022) - check if JNF is still required to build M1 JDK
declare -r jnf_dir="$top/prebuilts/jdk/studio/jdk11/mac-arm64/Contents/Home/Frameworks"
declare -r jnf_flags_param="-F$(realpath $jnf_dir) "

# Darwin lacks autoconf, install it for this build.
install_autoconf "$autoconf_dir" "$out_path"

# Configure
[[ -n "${quiet:-}" ]] || set -x
(
   mkdir -p "$build_dir"
   cd "$build_dir"
   PATH="$autoconf_dir/bin":$PATH bash +x "$top/external/jetbrains/JetBrainsRuntime/configure" \
     "${quiet:+--quiet}" \
     --disable-full-docs \
     --disable-warnings-as-errors \
     --with-boot-jdk="$boot_jdk" \
     --with-sysroot="$sysroot" \
     --with-freetype=bundled \
     --with-libpng=bundled \
     --with-native-debug-symbols=external \
     --with-stdc++lib=static \
     --with-toolchain-type=clang \
     --without-version-pre \
     --with-vendor-name="JetBrains s.r.o." \
     --with-version-opt="$(sed 's/^.*-//' "${top}/external/jetbrains/JetBrainsRuntime/build.txt")-${build_number}" \
     --openjdk-target=aarch64-apple-darwin \
     --with-extra-cflags="-arch arm64 ${jnf_flags_param} -fno-delete-null-pointer-checks" \
     --with-extra-cxxflags="-arch arm64 ${jnf_flags_param} " \
     --with-extra-ldflags="-arch arm64 ${jnf_flags_param}" \
     --with-jvm-features="shenandoahgc"
)

# Make
declare -r make_log_level=${quiet:+warn}
make -C "$build_dir" LOG=${make_log_level:-debug} ${quiet:+-s} images

# Dist
[[ -n "${dist_dir:-}" ]] || exit 0

rm -rf "$dist_dir"/{jdk.zip,jdk-debuginfo.zip,jdk-runtime.zip,build.log,configure.log}
declare -r bundle_dir=$(find $build_dir/images/jdk-bundle/ -type d -depth 1 -name 'jdk-*.jdk')

(
  cd "$build_dir/images/jdk-bundle"

  # Bundle JavaNativeFoundation
  if [ "${jnf_dir:-}" ]; then
   ditto "$(realpath $jnf_dir)" ${bundle_dir}/Contents/Home/Frameworks
  fi

  # Rewrite absolute references to rpath-relative one
  install_name_tool -change @rpath/JavaNativeFoundation.framework/Versions/A/JavaNativeFoundation @loader_path/../Frameworks/JavaNativeFoundation.framework/JavaNativeFoundation ${bundle_dir}/Contents/Home/lib/libawt.dylib

  zip -9rDy${quiet:+q} "$dist_dir"/jdk-bundle.zip . -x'*.dSYM/*' -x'*/man/*' -x'*/demo/*'
  zip -9rDy${quiet:+q} "$dist_dir"/jdk-debuginfo.zip . -i'*.dSYM/*'

  echo $'\n\n===================================='
  echo "JDK Bundle $dist_dir/jdk-bundle.zip"
  echo "Debug Symbols $dist_dir/jdk-debuginfo.zip"
  echo $'====================================\n\n'
)
cp "$build_dir"/build.log "$dist_dir"
cp "$build_dir"/configure-support/config.log "$dist_dir"/configure.log


#Assemble JDK-runtime
(
  mkdir -p  "${build_dir}/java-runtime"
  cd  "${build_dir}/java-runtime"

  # Use jlink from Boot JDK as we are cross-compiling
  "${boot_jdk}/bin/jlink" \
    --no-header-files \
    --no-man-pages \
    --compress=2 \
    --module-path="${build_dir}/images/jdk/jmods" \
    --add-modules $(xargs < ${top}/toolchain/jdk/build/jdk11-modules.list | sed s/" "/,/g) \
    --output "${build_dir}/java-runtime/Contents/Home"

  # Rewrite absolute references to rpath-relative one
  install_name_tool -change @rpath/JavaNativeFoundation.framework/Versions/A/JavaNativeFoundation @loader_path/../Frameworks/JavaNativeFoundation.framework/JavaNativeFoundation Contents/Home/lib/libawt.dylib

  ditto ${bundle_dir}/Contents/MacOS ./Contents/MacOS
  ditto ${bundle_dir}/Contents/Info.plist ./Contents/Info.plist

  zip -9rDy${quiet:+q} "${dist_dir}/jdk-runtime.zip" . -x'*.dSYM/*' -x'*/man/*' -x'*/demo/*'

  echo $'\n\n===================================='
  echo "JDK Runtime $dist_dir/jdk-runtime.zip"
  echo $'====================================\n\n'
)