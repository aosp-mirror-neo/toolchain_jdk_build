#!/bin/bash
#
# builds JBR21 for Windows. Expected to be called from build-jbr_next-win-x64.cmd wrapper


echo "In toolchain\jdk\build\build-jbr21-win-x64.sh..."

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

declare -r sources_dir="${top}/external/jetbrains/JetBrainsRuntime-next"
declare -r boot_jdk="$top/prebuilts/jdk/studio/jbrjdk21/windows-x64"

if [ -f "$dist_dir"/jdk.zip ]; then
  echo "Re-using existing JDK $dist_dir/jdk.zip"
else
  declare -r jbr_tag="$(sed 's/^.*b//' "$sources_dir/build.txt")"
  # Configure
  mkdir -p "$build_dir"
  [[ -n "${quiet:-}" ]] || set -x
  (
    echo "configuring build"
    cd "$build_dir"
    bash +x "$sources_dir/configure" \
     "${quiet:+--quiet}" \
     --with-vendor-name="JetBrains s.r.o." \
     --with-version-pre=$([ "$build_number" == "dev" ] && echo "dev" || echo "") \
     --without-version-build \
     --with-version-opt="$(numeric_build_number $build_number)-b$jbr_tag" \
     --with-extra-path="/cygdrive/c/tools/cygwin/bin" \
     --enable-cds=yes \
     --disable-ccache \
     --disable-absolute-paths-in-output \
     --disable-full-docs \
     --disable-warnings-as-errors \
     --with-boot-jdk="$boot_jdk" \
     --with-native-debug-symbols=zipped \
     --with-debug-level=release \
     --disable-jvm-feature-epsilongc \
     --disable-jvm-feature-parallelgc \
     --disable-jvm-feature-shenandoahgc \
     --disable-jvm-feature-zgc \
     --disable-jvm-feature-dtrace
  )
    echo "Configure done"
    echo "Making images ...."

  (
    declare -r make_log_level=${quiet:+warn}
    make -C "$build_dir" JOBS=1 LOG=${make_log_level:-debug} ${quiet:+-s} images
  )

  rm -rf "$dist_dir"/{jdk.zip,jdk-debuginfo.zip,jdk-runtime.zip,build.log,configure.log}
  (
    cd "$build_dir/images/jdk"
    rm -rf demo
    rm -rf man
    zip -9rDy${quiet:+q} "$dist_dir"/jdk.zip . -x'*.diz'
    zip -9rDy${quiet:+q} "$dist_dir"/jdk-debuginfo.zip . -i'*.diz'
  )
  cp "$build_dir"/build.log "$dist_dir"
  cp "$build_dir"/configure-support/config.log "$dist_dir"/configure.log
fi

echo "Creating java runtime ...."
(
  rm -rf "${out_path}/java-runtime" &&  mkdir "${out_path}/java-runtime"
  cd  "${out_path}/java-runtime"

  jbr_jdk_dir=$(make_target_dir "jdk")
  runtime_image_dir="${out_path}/java-runtime/image"
  unzip ${quiet:+-q} "${dist_dir}/jdk.zip" -d $jbr_jdk_dir

  # 1. add studio modules to jb/project/tools/common/modules.list
  # 2. remove trailing comas, and remove duplicates
  # 3. trim, and convert lines to coma-separated list
 declare modules=$(
   cat ${sources_dir}/jb/project/tools/common/modules.list ${top}/toolchain/jdk/build/studio-modules.list \
   | sed s/","/" "/g | sort | uniq \
   | grep -v 'jdk.internal.vm.compiler' \
   | xargs | sed s/" "/,/g
 )

  "${boot_jdk}/bin/jlink" \
    --no-header-files \
    --no-man-pages \
    --strip-debug \
    --compress=zip-9 \
    --module-path="${jbr_jdk_dir}/jmods" \
    --add-modules ${modules} \
    --output "${runtime_image_dir}"

  grep -v "^JAVA_VERSION" "${jbr_jdk_dir}/release" | grep -v "^MODULES" >> "${runtime_image_dir}/release"
  cp "${runtime_image_dir}/release" "${dist_dir}"

  cd ${runtime_image_dir}
  zip -9rDy${quiet:+q} "${dist_dir}/jdk-runtime.zip" .
  echo "Java Runtime Done"
)

echo "All Done!"