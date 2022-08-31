#!/bin/bash
#
# Builds JDK17 for aarch64, optionally creating distribution artifacts for it.
# Usage:
#   build-jetbrainsruntime17-darwin-aarch64.sh [-q] [-d <dist_dir>] [-o <out_dir>] -b <build_number>
# The JDK is built in OUT_DIR (or "out" if unset).
# If DIST_DIR is set, the following artifacts are created there:
#   jdk.zip              archive of the JDK distribution
#   jdk-runtime.zip
#   jdk-debuginfo.zip    .debuginfo files for JDK's shared libraries
#   configure.log
#   build.log
# Specify -q to suppress most of the output noise

source $(dirname $0)/build-jetbrainsruntime-common.sh

declare -r boot_jdk="$top/prebuilts/jdk/jdk17/darwin-x86"
declare -r boot_jdk_version=$($boot_jdk/bin/java -version 2>&1 | head -1 | cut -d'"' -f2)

echo "Building Mac Aarch64 JDK......."
echo "out_path=${out_path:-}"
echo "dist_dir=${dist_dir:-}"
echo "build_number=${build_number:-}"
echo "sysroot=${sysroot:-}"
echo "top=${top:-}"
echo "sdk_version=${sdk_version:-}"
echo "autoconf_dir=${autoconf_dir:-}"
echo "boot_jdk=${boot_jdk:-}"
echo "build_dir=${build_dir:-}"
echo "boot_jdk_version=${boot_jdk_version:-}"

# Darwin lacks autoconf, install it for this build.
install_autoconf "$autoconf_dir" "$out_path"

# Configure
[[ -n "${quiet:-}" ]] || set -x
(
   mkdir -p "$build_dir"
   cd "$build_dir"
   PATH="$autoconf_dir/bin":$PATH bash +x "$top/external/jetbrains/JetBrainsRuntime17/configure" \
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
         --with-version-opt="$(sed 's/^.*-//' "${top}/external/jetbrains/JetBrainsRuntime17/build.txt")-${build_number}" \
         --openjdk-target=aarch64-apple-darwin \
         --with-extra-cflags="-fno-delete-null-pointer-checks" \
         --with-jvm-features="shenandoahgc"
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
(
  cd "$bundle_dir"
  zip -9rDy${quiet:+q} "$dist_dir"/jdk.zip . --exclude 'Contents/Home/demo/*' --exclude 'Contents/Home/man/*' --exclude '*.dSYM*'
  zip -9rDy${quiet:+q} "$dist_dir"/jdk-debuginfo.zip . --include '*.dSYM*'
)
cp "$build_dir"/build.log "$dist_dir"
cp "$build_dir"/configure-support/config.log "$dist_dir"/configure.log

echo "Dist done"

# Java Runtime
(
  rm -rf "${build_dir}/java-runtime"
  mkdir -p  "${build_dir}/java-runtime"
  cd  "${build_dir}/java-runtime"

  # Use jlink from Boot JDK as we are cross-compiling
  "${boot_jdk}/bin/jlink" \
    --no-header-files \
    --no-man-pages \
    --compress=2 \
    --strip-debug \
    --module-path="${build_dir}/images/jdk/jmods" \
    --add-modules $(xargs < ${top}/external/jetbrains/JetBrainsRuntime17/jb/project/tools/common/modules.list | sed s/" "//g) \
    --output "${build_dir}/java-runtime/Contents/Home"

  grep -v "^JAVA_VERSION" "${build_dir}/jdk/release" | grep -v "^MODULES" >> "${build_dir}/java-runtime/release"
  cp "${build_dir}/java-runtime/release" "${dist_dir}"

  # Rewrite absolute references to rpath-relative one
  ditto ${bundle_dir}/Contents/MacOS ./Contents/MacOS
  ditto ${bundle_dir}/Contents/Info.plist ./Contents/Info.plist

  zip -9rDy${quiet:+q} "${dist_dir}/jdk-runtime.zip" .
)