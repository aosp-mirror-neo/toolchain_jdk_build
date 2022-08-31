#!/bin/bash
#
# builds JetBrainsRuntime17 for Windows. Expected to be called from build-jetbrainsruntime17-win.cmd wrapper

source $(dirname $0)/build-jetbrainsruntime-common.sh

## Convert Windows paths to unix/cygwin
build_dir=$(cygpath --unix --absolute "${build_dir}")
out_path=$(cygpath --unix --absolute "${out_path}")
dist_dir=$(cygpath --unix --absolute "${dist_dir}")
top=$(cygpath --unix --absolute "${top}")

echo "out_path=${out_path:-}"
echo "dist_dir=${dist_dir:-}"
echo "build_dir=${build_dir:-}"
echo "top=${top:-}"
echo "build_number=${build_number:-}"

# Configure
# clean up from previous builds
rm -rf "$build_dir"
mkdir -p "$build_dir"
[[ -n "${quiet:-}" ]] || set -x
(
    echo "configuring build"
    cd "$build_dir"
    bash +x "$top/external/jetbrains/JetBrainsRuntime17/configure" \
     "${quiet:+--quiet}" \
     --with-extra-path="/cygdrive/c/tools/cygwin/bin" \
     --with-jobs=1 \
     --enable-cds=yes \
     --disable-ccache \
     --disable-full-docs \
     --disable-warnings-as-errors \
     --with-boot-jdk="$top/prebuilts/jdk/jdk17/windows-x86" \
     --without-version-pre \
     --with-vendor-name="JetBrains s.r.o." \
     --with-version-opt="$(sed 's/^.*-//' "${top}/external/jetbrains/JetBrainsRuntime/build.txt")-${build_number}" \
     --with-jvm-features="shenandoahgc"
)
echo "Configure done"
(
echo "Making images ...."
# Make
make JOBS=1 LOG=debug -C "$build_dir" ${quiet:+-s} images
)

# Distribute jdk
[[ -n "${dist_dir:-}" ]] || exit 0

rm -rf "$dist_dir"/{jdk.zip,jdk-debuginfo.zip,jdk-runtime.zip,build.log,configure.log}
declare -r bundle_dir=$(find $build_dir/images/jdk-bundle/ -type d -depth 1 -name 'jdk-*.jdk')
(cd "$build_dir/images/jdk" &&
  zip -9rDy${quiet:+q} "$dist_dir"/jdk.zip . -x 'demo/*' -x'man/*' -x'*.map' -x'*.pdb' &&
  zip -9rDy${quiet:+q} "$dist_dir"/jdk-debuginfo.zip . -i'*.map' -i'*.pdb'
)

cp "$build_dir"/build.log "$dist_dir"
cp "$build_dir"/configure-support/config.log "$dist_dir"/configure.log

(
cd "${build_dir}"

"${build_dir}/images/jdk/bin/jlink" \
  --output "java-runtime" \
  --no-header-files \
  --no-man-pages \
  --compress=2 \
  --module-path="${build_dir}/images/jdk/jmods" \
  --add-modules $(xargs < ${top}/external/jetbrains/JetBrainsRuntime17/jb/project/tools/common/modules.list | sed s/" "//g)

grep -v "^JAVA_VERSION" "${build_dir}/jdk/release" | grep -v "^MODULES" >> "${build_dir}/java-runtime/release"
cp "${build_dir}/java-runtime/release" "${dist_dir}"

cd java-runtime
zip -9rDy${quiet:+q} "${dist_dir}/jdk-runtime.zip" .
)
