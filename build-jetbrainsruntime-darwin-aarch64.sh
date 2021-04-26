#!/bin/bash
#
# Builds JDK11 for aarch64, optionally creating distribution artifacts for it.
# Usage:
#   build-jetbrainsruntime-darwin.sh [-q] [-d <dist_dir>] [-o <out_dir>] [-f <jnf_dir>] -b <build_number>
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
Use <jnf_dir> to override JavaNativeFundation location
With -q, runs with minimum noise.
EOF
  exit 1
}

while getopts 'qb:d:o:f:' opt; do
  case $opt in
    b) build_number=$OPTARG ;;
    o) out_dir_option=$OPTARG;;
    d) dist_dir=$(make_target_dir $OPTARG) ;;
    f) jnf_dir=$OPTARG;;
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


## TODO change to JDK11 prebuilt, when it is checked in
# When this script was created there was only jdk9 prebuilt available, but to cross-compile boot jdk need to be 10 or 11
# so we build a 'normal' x64 jdk first, and use it as a bootstrap for aarch64
(
  echo "Building darwin-x86_64 jdk"
  OUT_DIR="$out_path/jdk_x86_64" BUILD_NUMBER="$build_number" bash +x $(dirname $0)/build-jetbrainsruntime-darwin.sh "-q" "-x"
)
declare -r boot_jdk=$(realpath "$out_path/jdk_x86_64/build/images/jdk")
declare -r boot_jdk_version=$($boot_jdk/bin/java -version 2>&1 | head -1 | cut -d'"' -f2)

if [ $(ver $boot_jdk_version) -ge $(ver 12) ] || [ $(ver $boot_jdk_version) -lt $(ver 10) ]; then
    echo "Boot JDK version must be 10 or 11"
    exit 1
fi

if [ "${jnf_dir:-}" ]; then
    declare -r jnf_flags_param="-F$(realpath $jnf_dir) "
else
    declare -r jnf_flags_param=""
fi


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
     --with-extra-cflags="-arch arm64 ${jnf_flags_param}" \
     --with-extra-cxxflags="-arch arm64 ${jnf_flags_param} " \
     --with-extra-ldflags="-arch arm64 ${jnf_flags_param}" \
     --with-jvm-features="shenandoahgc" \
     --with-extra-cflags="-fno-delete-null-pointer-checks"
)

# Make
declare -r make_log_level=${quiet:+warn}
make -C "$build_dir" LOG=${make_log_level:-debug} ${quiet:+-s} images

# Dist
[[ -n "${dist_dir:-}" ]] || exit 0

rm -rf "$dist_dir"/{jdk.zip,jdk-debuginfo.zip,jdk-runtime.zip,build.log,configure.log}
(
  declare -r bundle_dir=$(find $build_dir/images/jdk-bundle/ -type d -depth 1 -name 'jdk-*.jdk')
  cd "$build_dir/images/jdk-bundle"

  # Bundle JavaNativeFoundation
  if [ "${jnf_dir:-}" ]; then
   ditto "$(realpath $jnf_dir)" ${bundle_dir}/Contents/Home/Frameworks
  fi

  # Rewrite absolute references to rpath-relative one
  install_name_tool -change @rpath/JavaNativeFoundation.framework/Versions/A/JavaNativeFoundation @loader_path/../Frameworks/JavaNativeFoundation.framework/JavaNativeFoundation ${bundle_dir}/Contents/Home/lib/libawt.dylib

  zip -9rDy${quiet:+q} "$dist_dir"/jdk-bundle.zip . -x 'demo/*' -x'man/*' -x'*.dSYM'
  zip -9rDy${quiet:+q} "$dist_dir"/jdk-debuginfo.zip . -i'*.dSYM'
)
cp "$build_dir"/build.log "$dist_dir"
cp "$build_dir"/configure-support/config.log "$dist_dir"/configure.log

# Use jlink from Boot JDK and newly built one is for different CPU architecture
"${boot_jdk}/bin/jlink" \
  --no-header-files \
  --no-man-pages \
  --compress=2 \
  --module-path="${build_dir}/images/jdk/jmods" \
  --add-modules java.base,java.compiler,java.datatransfer,java.desktop,java.instrument,java.logging,java.management,java.management.rmi,java.naming,java.net.http,java.prefs,java.rmi,java.scripting,java.se,java.security.jgss,java.security.sasl,java.smartcardio,java.sql,java.sql.rowset,java.transaction.xa,java.xml,java.xml.crypto,jdk.accessibility,jdk.aot,jdk.attach,jdk.charsets,jdk.compiler,jdk.crypto.cryptoki,jdk.crypto.ec,jdk.dynalink,jdk.hotspot.agent,jdk.httpserver,jdk.internal.ed,jdk.internal.jvmstat,jdk.internal.le,jdk.internal.vm.ci,jdk.internal.vm.compiler,jdk.internal.vm.compiler.management,jdk.javadoc,jdk.jdi,jdk.jdwp.agent,jdk.jfr,jdk.jlink,jdk.jsobject,jdk.localedata,jdk.management,jdk.management.agent,jdk.management.jfr,jdk.naming.dns,jdk.naming.rmi,jdk.net,jdk.pack,jdk.scripting.nashorn,jdk.scripting.nashorn.shell,jdk.sctp,jdk.security.auth,jdk.security.jgss,jdk.unsupported,jdk.xml.dom,jdk.zipfs \
  --output "${build_dir}/java-runtime"

# Rewrite absolute references to rpath-relative one
install_name_tool -change @rpath/JavaNativeFoundation.framework/Versions/A/JavaNativeFoundation @loader_path/../Frameworks/JavaNativeFoundation.framework/JavaNativeFoundation ${build_dir}/java-runtime/lib/libawt.dylib
(cd "${build_dir}/java-runtime" && zip -9rDy${quiet:+q} "${dist_dir}/jdk-runtime.zip" .)
