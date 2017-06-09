
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

ln -sf ${JDK_SRC}/jdk8u/* ${OUT}/
for i in $(cd ${JDK_SRC}; ls -d jdk8u_*); do
    rm -f ${OUT}/${i/jdk8u_/}
    ln -sf ${JDK_SRC}/${i} ${OUT}/${i/jdk8u_/}
done
