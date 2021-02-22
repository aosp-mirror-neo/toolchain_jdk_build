#!/bin/bash
#
# Builds JDK11, optionally creating distribution artifacts for it.
# Usage:
#   build-jetbrainsruntime-darwin.sh [-q]
# The JDK is built in OUT_DIR (or "out" if unset).
# If DIST_DIR is set, the following artifacts are created there:
#   jdk.zip              archive of the JDK distribution
#   jdk-debuginfo.zip    .debuginfo files for JDK's shared libraries
#   configure.log
#   build.log
# Specify -q to suppress most of the output noise

set -eu
declare -r prog="${0##*/}"

function usage() {
  cat <<EOF
Usage:
    $prog [-q]
The JDK is built in OUT_DIR (or "out" if unset).
If DIST_DIR is set, artifacts are created there.
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

if [[ -n "${DIST_DIR:-}" ]]; then
  dist_dir="$(make_target_dir "${DIST_DIR}")"
fi

while getopts 'qd:' opt; do
  case $opt in
    q) quiet=t ;;
    *) usage ;;
  esac
done
shift $(($OPTIND-1))
(($#==0)) || usage

declare -r sdk_version=$(xcrun --show-sdk-version)
[[ "${sdk_version}" == "10.9" || "${sdk_version}" == "10.10" ]] || \
    { echo "Xcode sdk version 10.9 or 10.10 is required"; exit 1; }

declare -r out_path=$(make_target_dir "${OUT_DIR:-"out"}")
declare -r sysroot=$(xcrun --show-sdk-path)
declare -r build_dir="$out_path/build"
declare -r top=$(realpath "$(dirname "$0")/../../..")
declare -r clang_bin="$top/prebuilts/clang/host/darwin-x86/clang-r353983c/bin"
declare -r autoconf_dir=$(make_target_dir "$out_path/autoconf")

# Darwin lacks autoconf, install it for this build.
install_autoconf "$autoconf_dir" "$out_path"

# Configure
mkdir -p "$build_dir"
[[ -n "${quiet:-}" ]] || set -x
(cd "$build_dir" &&
   bash +x "$top/external/jetbrains/JetBrainsRuntime/configure" \
     "${quiet:+--quiet}" \
     --disable-full-docs \
     --disable-warnings-as-errors \
     --with-boot-jdk="$top/prebuilts/jdk/jdk9/darwin-x86" \
     --with-sysroot="$sysroot"\
     --with-freetype=bundled \
     --with-libpng=bundled \
     --with-native-debug-symbols=external \
     --with-stdc++lib=static \
     --with-toolchain-type=clang \
     --with-tools-dir="$clang_bin" \
     --without-version-pre \
     --with-vendor-name="JetBrains s.r.o." \
     --with-version-opt="$(sed 's/^.*-//' "${top}/external/jetbrains/JetBrainsRuntime/build.txt")-${BUILD_NUMBER}" \
     --with-zlib=bundled \
     AR=llvm-ar NM=llvm-nm OBJDUMP=llvm-objdump STRIP=llvm-strip
)

# Make
declare -r make_log_level=${quiet:+warn}
make -C "$build_dir" LOG=${make_log_level:-debug} ${quiet:+-s} images
[[ -n "${dist_dir:-}" ]] || exit 0

# Dist
rm -rf "$dist_dir"/{jdk.zip,jdk-debuginfo.zip,jdk-runtime.zip,build.log,configure.log}
(cd "$build_dir/images/jdk" &&
  zip -9rDy${quiet:+q} "$dist_dir"/jdk.zip . -x 'demo/*' -x'man/*' -x'*.debuginfo' &&
  zip -9rDy${quiet:+q} "$dist_dir"/jdk-debuginfo.zip . -i'*.debuginfo'
)
cp "$build_dir"/build.log "$dist_dir"
cp "$build_dir"/configure-support/config.log "$dist_dir"/configure.log

"${build_dir}/images/jdk/bin/jlink" \
  --no-header-files \
  --no-man-pages \
  --compress=2 \
  --module-path="${build_dir}/images/jdk/jmods" \
  --add-modules java.base,java.compiler,java.datatransfer,java.desktop,java.instrument,java.logging,java.management,java.management.rmi,java.naming,java.net.http,java.prefs,java.rmi,java.scripting,java.se,java.security.jgss,java.security.sasl,java.smartcardio,java.sql,java.sql.rowset,java.transaction.xa,java.xml,java.xml.crypto,jdk.accessibility,jdk.aot,jdk.attach,jdk.charsets,jdk.compiler,jdk.crypto.cryptoki,jdk.crypto.ec,jdk.dynalink,jdk.hotspot.agent,jdk.httpserver,jdk.internal.ed,jdk.internal.jvmstat,jdk.internal.le,jdk.internal.vm.ci,jdk.internal.vm.compiler,jdk.internal.vm.compiler.management,jdk.javadoc,jdk.jdi,jdk.jdwp.agent,jdk.jfr,jdk.jlink,jdk.jsobject,jdk.localedata,jdk.management,jdk.management.agent,jdk.management.jfr,jdk.naming.dns,jdk.naming.rmi,jdk.net,jdk.pack,jdk.scripting.nashorn,jdk.scripting.nashorn.shell,jdk.sctp,jdk.security.auth,jdk.security.jgss,jdk.unsupported,jdk.xml.dom,jdk.zipfs \
  --output "${build_dir}/java-runtime"
(cd "${build_dir}/java-runtime" && zip -9rDy${quiet:+q} "${dist_dir}/jdk-runtime.zip" .)