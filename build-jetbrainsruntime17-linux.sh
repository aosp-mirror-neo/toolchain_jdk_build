#!/bin/bash
#
# Builds JDK17, optionally creating distribution artifacts for it.
# Usage:
#   build-jetbrainsruntime17-linux.sh [-q]
# The JDK is built in OUT_DIR (or "out" if unset).
# If DIST_DIR is set, the following artifacts are created there:
#   jdk.zip              archive of the JDK distribution
#   jdk-debuginfo.zip    .debuginfo files for JDK's shared libraries
#   configure.log
#   build.log
# Specify -q to suppress most of the output noise

source $(dirname $0)/build-jetbrainsruntime-common.sh

# "Installs" given Debian packages into specified directory.
function unpack_dependencies() {
  local -r target_dir="$1"
  local -r ar="$clang_bin/llvm-ar"
  shift
  mkdir -p "$target_dir"
  for deb in "$@"; do
    # Debian package is actually 'ar' archive. The package files are in data.tar.<type>
    # member. Extract and untar it.
    case $("$ar" -t "$deb" | grep data.tar) in
      data.tar.xz)
        "$ar" -p "$deb" data.tar.xz | (cd "$target_dir" && tar -Jx) ;;
      data.tar.bz2)
        "$ar" -p "$deb" data.tar.bz2 | (cd "$target_dir" && tar -jx) ;;
      data.tar.gz)
        "$ar" -p "$deb" data.tar.gz | (cd "$target_dir" && tar -zx) ;;
      *)
        printf "%s does not contain expected archive\n" "$deb"
        exit 1
        ;;
    esac
    [[ -n "${quiet:-}" ]] || printf "Unpacked %s\n" "$deb"
  done

  # Rewrite absolute symlinks that point outside the sysroot to relative
  # symlinks to the corresponding files in the sysroot.
  for link in $(find "${target_dir}" -type l -lname '/*'); do
    target=$(readlink ${link})
    relative_target_dir=$(python -c 'import os.path, sys; print(os.path.relpath(*sys.argv[1:]))' ${target_dir} $(dirname ${link}))
    relative_target=${relative_target_dir}/${target}
    ln -sfn ${relative_target} ${link}
  done
}

# Prepare
unpack_dependencies "$sysroot" $top/toolchain/jdk/deps/*.deb

function dist_logs() {
    [[ -n "${dist_dir:-}" && -e "${build_dir}/build.log" ]] && cp "${build_dir}/build.log" "${dist_dir}/"
    [[ -n "${dist_dir:-}" && -e "${build_dir}/configure-support/config.log" ]] && cp "${build_dir}/configure-support/config.log" "${dist_dir}/"
}
trap dist_logs EXIT


# Configure tools needed to build the JDK
mkdir -p "$build_dir"
[[ -n "${quiet:-}" ]] || set -x
(cd "$build_dir" &&
   bash +x "$top/external/jetbrains/JetBrainsRuntime17/configure" \
        "${quiet:+--quiet}" \
        --disable-full-docs \
        --disable-warnings-as-errors \
        --with-alsa-include="$sysroot/usr/include" \
        --with-alsa-lib="$sysroot/usr/lib/x86_64-linux-gnu" \
        --with-boot-jdk="$top/prebuilts/jdk/jdk17/linux-x86" \
        --with-cups-include="$sysroot/usr/include" \
        --with-toolchain-type=clang \
        --with-libpng=bundled \
        --with-stdc++lib=static \
        --with-toolchain-path="$clang_bin" \
        --with-vendor-name="JetBrains s.r.o." \
        --with-version-opt="$(sed 's/^.*-//' "${top}/external/jetbrains/JetBrainsRuntime17/build.txt")-${build_number}" \
        --with-zlib=bundled \
        --x-libraries="$sysroot/usr/lib/x86_64-linux-gnu" \
        --x-includes="$sysroot/usr/include" \
        --without-version-pre \
        --with-native-debug-symbols=external \
        --with-freetype-include="$top/external/jetbrains/JetBrainsRuntime17/src/java.desktop/share/native/libfreetype/include" \
        --with-freetype-lib="$sysroot/usr/lib/x86_64-linux-gnu" \
        --with-freetype=system \
        --with-sysroot="$sysroot" \
        --with-extra-cflags="--sysroot=$sysroot -fno-delete-null-pointer-checks" \
        --with-extra-cxxflags="--sysroot=$sysroot -fno-delete-null-pointer-checks" \
        --with-extra-ldflags="--sysroot=$sysroot -fuse-ld=lld" \
        AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip
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

# 1. add studio mudules to jb/project/tools/common/modules.list
# 2. remove trailing comas, and remove duplicates
# 3. trim, and convert lines to coma-separated list
declare modules=$(
  cat ${top}/external/jetbrains/JetBrainsRuntime17/jb/project/tools/common/modules.list ${top}/toolchain/jdk/build/studio-modules.list \
  | sed s/","/" "/g | sort | uniq \
  | xargs | sed s/" "/,/g
)

# Build the Java Runtime
"${build_dir}/images/jdk/bin/jlink" \
  --no-header-files \
  --no-man-pages \
  --compress=2 \
  --module-path="${build_dir}/images/jdk/jmods" \
  --add-modules ${modules} \
  --output "${build_dir}/java-runtime"

grep -v "^JAVA_VERSION" "${build_dir}/jdk/release" | grep -v "^MODULES" >> "${build_dir}/java-runtime/release"
cp "${build_dir}/java-runtime/release" "${dist_dir}"
(cd "${build_dir}/java-runtime" && zip -9rDy${quiet:+q} "${dist_dir}/jdk-runtime.zip" .)
