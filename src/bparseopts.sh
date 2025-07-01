# like zparseopts but slightly different:
#  - None of the flags are supported, it acts as if -E and -D were specified
#  - It sets an array variable $positionals with arguments left after parsing is finished
#  - It sets an array special_positionals to $positionals
#  - If -- was used then special_positionals will contain all items before the -- and
#    $extra_positionals will contain all items after the --
#  - "a=arg=value" can be specified, then if -a is found in the arguments $arg is set to "value"
#  - long options are not supported
#  - The following are not supported:
#    - a::=value
#    - a:-=value
#    - a+:=value

function bparseopts() {
  local getoptstr=""
  local slice_from=1

  declare -A opts
  declare -A with_param

  while [[ $1 != -- ]]; do
    local desc=${1%%=*}
    local flag=${desc%:}

    if [[ $flag != $desc ]]; then
      with_param[$flag]=1
    fi

    local config=${1#*=}
    opts[$flag]=$config
    shift
  done

  # remove the --
  shift

  positionals=()
  while [[ ${#@} -ne 0 ]]; do
    if [[ $1 = -- ]]; then
      special_positionals="${positionals[@]}"
      shift
      positionals+=("$@")
      extra_positionals=("$@")
      break
    fi

    if [[ $1 != -? ]]; then
      positionals+=("$1")
      shift
      continue
    fi

    local flag=${1:1:1}
    local opt=${opts[$flag]}

    if [[ ! $opt ]]; then
      echo >&2 "unrecognised argument $1"
      exit 1
    fi

    if [[ $opt = *=* ]]; then
      declare -g "$opt"
    elif [[ ${with_param[$flag]} ]]; then
      shift
      local param=$1
      declare -g "$opt=$param"
    else
      declare -g "$opt=$1"
    fi

    shift
  done

  if [[ ! $special_positionals ]]; then
    special_positionals="${positionals[@]}"
  fi
}
