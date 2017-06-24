
JDK_UPDATE_VERSION=152
JDK_BUILD_NUMBER=1

if [ -z "${OUT_DIR}" ]; then
    echo "OUT_DIR must be set"
    exit 1
fi

mkdir -p ${OUT_DIR}
OUT=$(cd ${OUT_DIR} && pwd)
TOP=$(cd $(dirname $0)/../../.. && pwd)
JDK_SRC=${TOP}/external/jetbrains

case $(uname) in
    Linux)
        BUILD_TOOLS=${TOP}/prebuilts/build-tools/linux-x86/bin
        ;;
    Darwin)
        BUILD_TOOLS=${TOP}/prebuilts/build-tools/darwin-x86/bin
        ;;
    *) echo "unknown OS:" $(uname) && exit 1;;
esac

ln -sf ${JDK_SRC}/jdk8u/* ${OUT}/
for i in $(cd ${JDK_SRC}; ls -d jdk8u_*); do
    rm -f ${OUT}/${i/jdk8u_/}
    ln -sf ${JDK_SRC}/${i} ${OUT}/${i/jdk8u_/}
done

function soong_zip() {
    ${BUILD_TOOLS}/soong_zip -o $1 -C $2 -l <(find $2 | sort)
}

function sanitize_zips() {
    for i in $(find ${1} -type f \( -name "*.jar" -o -name "*.zip" -o -name "*.sym" \) ); do
        ${BUILD_TOOLS}/zip2zip -j -t -i $i -o $i.tmp
        mv -f $i.tmp $i
    done
}
