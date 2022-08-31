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

source $(dirname $0)/build-jetbrainsruntime-common.sh

declare -r sdk_version=$(xcrun --show-sdk-version)
[ $(ver $sdk_version) -ge $(ver 11.1) ] ||
    {
        echo "Xcode sdk version 11.1 or later is required (Xcode 12.3 or later)"
        echo "selected Xcode version: $sdk_version"
        echo "selected Xcode path: $(xcrun --show-sdk-path)"
        exit 1
    }

declare -r boot_jdk="$top/prebuilts/jdk/studio/jdk11/mac/Contents/Home"
declare -r boot_jdk_version=$($boot_jdk/bin/java -version 2>&1 | head -1 | cut -d'"' -f2)

echo "Building Aarch64 JDK......."
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

  zip -9rDy${quiet:+q} "$dist_dir"/jdk.zip . --exclude 'Contents/Home/demo/*' --exclude 'Contents/Home/man/*' --exclude '*.dSYM*'
  zip -9rDy${quiet:+q} "$dist_dir"/jdk-debuginfo.zip . --include '*.dSYM*'

  echo $'\n\n===================================='
  echo "JDK Bundle $dist_dir/jdk-bundle.zip"
  echo "Debug Symbols $dist_dir/jdk-debuginfo.zip"
  echo $'====================================\n\n'
)
cp "$build_dir"/build.log "$dist_dir"
cp "$build_dir"/configure-support/config.log "$dist_dir"/configure.log

echo "Dist done"

# Java Runtime
(
  rm -rf "${build_dir}/java-runtime"
  mkdir -p  "${build_dir}/java-runtime"
  cd  "${build_dir}/java-runtime"

  if grep -q 'jdk.aot' ${top}/toolchain/jdk/build/jetbrainsruntime-modules.list
  then
      echo "Excluding jdk.aot"
      cat ${top}/toolchain/jdk/build/jetbrainsruntime-modules.list | grep -v 'jdk.aot\|jdk.internal.vm.compiler' > "${build_dir}/aarch64-modules.list"
  else
      cat ${top}/toolchain/jdk/build/jetbrainsruntime-modules.list > "${build_dir}/aarch64-modules.list"
  fi

  # Use jlink from Boot JDK as we are cross-compiling
  "${boot_jdk}/bin/jlink" \
    --no-header-files \
    --no-man-pages \
    --compress=2 \
    --strip-debug \
    --module-path="${build_dir}/images/jdk/jmods" \
    --add-modules $(xargs < ${build_dir}/aarch64-modules.list | sed s/" "/,/g) \
    --output "${build_dir}/java-runtime/Contents/Home"

  grep -v "^JAVA_VERSION" "${build_dir}/jdk/release" | grep -v "^MODULES" >> "${build_dir}/java-runtime/release"
  cp "${build_dir}/java-runtime/release" "${dist_dir}"
  # Rewrite absolute references to rpath-relative one
  install_name_tool -change @rpath/JavaNativeFoundation.framework/Versions/A/JavaNativeFoundation @loader_path/../Frameworks/JavaNativeFoundation.framework/JavaNativeFoundation Contents/Home/lib/libawt.dylib

  ditto ${bundle_dir}/Contents/MacOS ./Contents/MacOS
  ditto ${bundle_dir}/Contents/Info.plist ./Contents/Info.plist

  zip -9rDy${quiet:+q} "${dist_dir}/jdk-runtime.zip" .

  echo $'\n\n===================================='
  echo "JDK Runtime $dist_dir/jdk-runtime.zip"
  echo $'====================================\n\n'
)