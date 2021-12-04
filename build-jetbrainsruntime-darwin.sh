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

source $(dirname $0)/build-jetbrainsruntime-common.sh

echo "Building Mac JDK......."
echo "out_path=${out_path:-}"
echo "dist_dir=${dist_dir:-}"
echo "sysroot=${sysroot:-}"
echo "build_dir=${build_dir:-}"
echo "top=${top:-}"
echo "clang_bin=${clang_bin:-}"
echo "autoconf_dir=${autoconf_dir:-}"
echo "build_number=${build_number:-}"

# Darwin lacks autoconf, install it for this build.
install_autoconf "$autoconf_dir" "$out_path"

# Configure
mkdir -p "$build_dir"
[[ -n "${quiet:-}" ]] || set -x
(cd "$build_dir" &&
    PATH="$autoconf_dir/bin":$PATH bash +x "$top/external/jetbrains/JetBrainsRuntime/configure" \
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
     --with-version-opt="$(sed 's/^.*-//' "${top}/external/jetbrains/JetBrainsRuntime/build.txt")-${build_number}" \
     --with-zlib=bundled \
     --with-jvm-features="shenandoahgc" \
     --with-extra-cflags="-fno-delete-null-pointer-checks" \
     AR=llvm-ar NM=llvm-nm OBJDUMP=llvm-objdump STRIP=llvm-strip
)


echo "Configure done"
echo "Making images ...."

# Make
declare -r make_log_level=${quiet:+warn}
make -C "$build_dir" LOG=${make_log_level:-debug} ${quiet:+-s} images


# Dist
[[ -n "${dist_dir:-}" ]] || exit 0

rm -rf "$dist_dir"/{jdk.zip,jdk-debuginfo.zip,jdk-runtime.zip,build.log,configure.log}
declare -r bundle_dir=$(find $build_dir/images/jdk-bundle/ -type d -depth 1 -name 'jdk-*.jdk')
(cd "$build_dir/images/jdk" &&
  zip -9rDy${quiet:+q} "$dist_dir"/jdk.zip . -x 'demo/*' -x'man/*' -x'*.dSYM' &&
  zip -9rDy${quiet:+q} "$dist_dir"/jdk-debuginfo.zip . -i'*.dSYM'
)
cp "$build_dir"/build.log "$dist_dir"
cp "$build_dir"/configure-support/config.log "$dist_dir"/configure.log


# Java Runtime
(
  mkdir -p  "${build_dir}/java-runtime"
  cd  "${build_dir}/java-runtime"

  "${build_dir}/bin/jlink" \
    --no-header-files \
    --no-man-pages \
    --compress=2 \
    --module-path="${build_dir}/images/jdk/jmods" \
    --add-modules $(xargs < ${top}/toolchain/jdk/build/jetbrainsruntime-modules.list | sed s/" "/,/g) \
    --output "${build_dir}/java-runtime/Contents/Home"

  ditto ${bundle_dir}/Contents/MacOS ./Contents/MacOS
  ditto ${bundle_dir}/Contents/Info.plist ./Contents/Info.plist

  zip -9rDy${quiet:+q} "${dist_dir}/jdk-runtime.zip" .
)