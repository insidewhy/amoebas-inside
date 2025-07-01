declare -A required_sources

get_root_dir() {
  if [[ $rootdir ]]; then
    echo "$rootdir"
  else
    local backup_cwd="$PWD"
    while [[ ! -d .git ]]; do
      cd ..
      if [[ $PWD = . ]]; then
        fail "Could not find root directory"
      fi
    done
    rootdir="$(readlink -f .)"
    echo "$rootdir"
  fi
}

# like "source" but only requires once
require() {
  local path="$(readlink -f "$1")"
  if [[ ! ${required_sources[$path]} ]]; then
    source $path "${@:2}"
    required_sources[$path]=1
  fi
}

# "require" relative to the root directory
require_root() {
  require "$(get_root_dir)/$1" "${@:2}"
}

require_lib() {
  require_relative "$1" "${@:2}"
}

require_relative() {
  require "$(dirname ${BASH_SOURCE[1]})/$1" "${@:2}"
}

pushd_silent() {
  pushd >/dev/null $1
}

popd_silent() {
  popd >/dev/null
}

pushd_relative() {
  pushd_silent "$(dirname "${BASH_SOURCE[1]}")/$1"
}

pushd_root() {
  pushd_silent "$(get_root_dir)/$1"
}

path_relative() {
  echo "$(dirname "${BASH_SOURCE[1]}")/$1"
}

path_root() {
  echo "$(get_root_dir)/$1"
}

run_relative() {
  "$(dirname "${BASH_SOURCE[1]}")/$1" "${@:2}"
}

COLOR_RED='\033[0;31m'
COLOR_BOLD_RED='\033[1;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RESET='\033[0m' # No Color

log_info() {
  echo >&2 -e "${COLOR_GREEN}[info]${COLOR_RESET}" "$@"
}

log_warn() {
  echo >&2 -e "${COLOR_YELLOW}[warn]${COLOR_RESET}" "$@"
}

log_error() {
  echo >&2 -e "${COLOR_RED}[error]${COLOR_RESET}" "$@"
}

log_fatal() {
  echo >&2 -e "${COLOR_BOLD_RED}[fatal]${COLOR_RESET}" "$@"
}

warn() {
  log_warn "$@"
}

fail() {
  log_fatal "$@"
  exit 1
}
