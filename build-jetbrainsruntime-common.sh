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

# Sanitize build number for `--with-version-opt` configure option
# Remove all non numeric symbols, return `0` if input don't have any numbers in it
function numeric_build_number {
  local -r numbers=$(echo "$1" | tr -dc '[^0-9]')
  echo ${numbers:-"0"}
}

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

function source_date_epoch() {
  cd $1
  # https://htmlpreview.github.io/?https://raw.githubusercontent.com/openjdk/jdk/master/doc/building.html#reproducible-builds
  # https://reproducible-builds.org/docs/source-date-epoch/
  if source_timestamp=$(git log -1 --pretty=%ct); then
   echo $source_timestamp
  else
   find . -type f -print0 | xargs -0 stat -f "%m %N" | sort -rn | head -1 | cut -f1 -w
  fi
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
declare out_path=$(make_target_dir "${out_dir_option}")
declare dist_dir="$(make_target_dir "${dist_dir_option}")"
declare build_dir="$out_path/build"
declare top=$(realpath "$(dirname "$0")/../../..")
declare -r autoconf_dir=$(make_target_dir "$out_path/autoconf")

case $(uname) in
  Linux)
    declare -r clang_bin="$top/prebuilts/clang/host/linux-x86/clang-r574158/bin"
    declare -r sysroot="$out_path/sysroot"
    ;;
  Darwin)
    declare -r clang_bin="$top/prebuilts/clang/host/darwin-x86/clang-r487747c/bin"
    declare -r sysroot=$(xcrun --show-sdk-path)
    ;;
  CYGWIN*) # Windows Cygwin
    ;;
  *) echo "unknown OS:" $(uname) && exit 1;;
esac

[[ -n "${quiet:-}" ]] || set -x