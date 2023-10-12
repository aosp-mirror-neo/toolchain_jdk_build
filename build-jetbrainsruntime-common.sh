set -eu
set -o pipefail

case $(uname) in
  Darwin)
   # Darwin does not have realpath.
   realpath() {
     cd $1 && pwd
   }
   ;;
esac

# Creates the directory if it does not exist and returns its absolute path
function make_target_dir() {
  mkdir -p "$1" && realpath "$1"
}

# Converts version string to comparable number `12.3` -> 012003000000. Works for at most 4 fields
function ver { printf "%03d%03d%03d%03d" $(echo "$1" | tr '.' ' '); }

# Installs autoconf into specified directory. The second argument is working directory.
function install_autoconf() {
  local -r workdir=$(make_target_dir "$2")
  local -r installdir=$(make_target_dir "$1")
  tar -C "$workdir" -xzf "$top/toolchain/jdk/deps/src/autoconf-2.69.tar.gz"
  (cd "$workdir"/autoconf-2.69 &&
     ./configure --prefix="$installdir" ${quiet:+--quiet} &&
     make ${quiet:+-s} install
  )
}

function usage() {
  declare -r prog="${0##*/}"
  cat <<EOF
Usage:
    $prog [-q] [-d <dist_dir>] [-o <out_dit>] -b <build_number>
The JDK is built in <out_dir> (or "out" if unset).
If <dist_dir> is set, artifacts are created there.
Specify JBR build number with <build_number>
With -q, runs with minimum noise.
EOF
  exit 1
}


while getopts 'qb:d:o:' opt; do
  case $opt in
    b) build_number=$OPTARG ;;
    o) out_dir_option=$OPTARG;;
    d) dist_dir_option=$OPTARG;;
    q) quiet=t ;;
    *) usage ;;
  esac
done
shift $(($OPTIND-1))
(($#==0)) || usage

# use ENV values or defaults if command line parameters are not set
if [ -z "${out_dir_option:-}" ]; then
    out_dir_option=${OUT_DIR:-"out"}
fi

if [ -z "${build_number:-}" ]; then
    build_number=${BUILD_NUMBER:-"dev"}
fi

if [ -z "${dist_dir_option:-}" ]; then
    dist_dir_option=${DIST_DIR:-"$out_dir_option/dist"}
fi

# Create output directories
declare -r out_path=$(make_target_dir "${out_dir_option}")
declare -r dist_dir="$(make_target_dir "${dist_dir_option}")"
declare -r build_dir="$out_path/build"
declare -r top=$(realpath "$(dirname "$0")/../../..")
declare -r autoconf_dir=$(make_target_dir "$out_path/autoconf")

case $(uname) in
  Linux)
    declare -r clang_bin="$top/prebuilts/clang/host/linux-x86/clang-r450784e/bin"
    declare -r sysroot="$out_path/sysroot"
    ;;
  Darwin)
    declare -r clang_bin="$top/prebuilts/clang/host/darwin-x86/clang-r450784e/bin"
    declare -r sysroot=$(xcrun --show-sdk-path)
    ;;
  CYGWIN*) # Windows Cygwin
    ;;
  *) echo "unknown OS:" $(uname) && exit 1;;
esac

[[ -n "${quiet:-}" ]] || set -x