#!/bin/bash
#
# builds JetBrainsRuntime for Windows. Expected to be called from build-jetbrainsruntime-win.cmd wrapper

echo "In build-jetbrainsruntime-win.sh"
echo "Building Windows JetBrainsRuntime......."
echo "Build arguments: $@"

# remove msys2 from PATH
export PATH=/usr/local/bin:/usr/bin:/cygdrive/c/Windows/system32:/cygdrive/c/Windows

source $(dirname $0)/build-jetbrainsruntime-common.sh

if [ -z "${quiet:-}" ]; then
    echo "Environment variables:"
    echo "==================================================="
    printenv
    echo "==================================================="
    set -x
fi

# Convert Windows paths to unix/cygwin
build_dir=$(cygpath --unix --absolute "${build_dir}")
out_path=$(cygpath --unix --absolute "${out_path}")
dist_dir=$(cygpath --unix --absolute "${dist_dir}")
top=$(cygpath --unix --absolute "${top}")
USER=builduser

echo "out_path=${out_path:-}"
echo "dist_dir=${dist_dir:-}"
echo "build_dir=${build_dir:-}"
echo "top=${top:-}"
echo "build_number=${build_number:-}"

echo "Cleaning up any previous build files"
rm -rf  "$build_dir"
mkdir -p "$build_dir"
(
  echo "Configure ...."
  cd "$build_dir"

  # TODO try to symlink VS path to shorter one, to see if it helps with build stability
  #     --with-tools-dir="${out_path}/vs" \

  # TODO remove --with-jobs=1 when build stability improves, this is a workaround

  "$top/external/jetbrains/JetBrainsRuntime/configure" \
     "${quiet:+--quiet}" \
     --disable-full-docs \
     --with-native-debug-symbols=zipped \
     --disable-warnings-as-errors \
     --with-boot-jdk="$top/prebuilts/jdk/studio/jdk11/win" \
     --without-version-pre \
     --with-vendor-name="JetBrains s.r.o." \
     --disable-absolute-paths-in-output \
     --with-version-opt="$(sed 's/^.*-//' "${top}/external/jetbrains/JetBrainsRuntime/build.txt")-${build_number}" \
     --enable-cds=yes \
     --disable-ccache \
     --with-jobs=1 \
     --with-jvm-features="shenandoahgc"
)

(
    echo "Making images ...."
    declare make_log_level=warn,cmdlines
    if [ -z "${quiet:-}" ]; then
        make_log_level=debug,cmdlines
    fi
    cd "$build_dir"
    make clean || true  # ignore errors if any
    make LOG=${make_log_level} ${quiet:+-s} images
)



# Dist
[[ -n "${dist_dir:-}" ]] || exit 0

rm -rf "$dist_dir"/{jdk.zip,jdk-debuginfo.zip,jdk-runtime.zip,build.log,configure.log}

(cd "$build_dir/images/jdk" &&
  zip -9rDy${quiet:+q} "$dist_dir"/jdk.zip . -x 'demo/*' -x'man/*' -x'*.map' -x'*.pdb' &&
  zip -9rDy${quiet:+q} "$dist_dir"/jdk-debuginfo.zip . -i'*.map' -i'*.pdb'
)
cp "$build_dir"/build.log "$dist_dir"
cp "$build_dir"/configure-support/config.log "$dist_dir"/configure.log


# Java Runtime
(
  cd  "${build_dir}"

  "${build_dir}/images/jdk/bin/jlink" \
    --no-header-files \
    --no-man-pages \
    --compress=2 \
    --module-path="${build_dir}/images/jdk/jmods" \
    --add-modules $(xargs < ${top}/toolchain/jdk/build/jetbrainsruntime-modules.list | sed s/" "/,/g) \
    --output "java-runtime"

  cd java-runtime
  zip -9rDy${quiet:+q} "${dist_dir}/jdk-runtime.zip" .
)