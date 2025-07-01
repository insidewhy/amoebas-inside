function confirm() {
  local confirmation
  while true; do
    echo -e -n "$*[yN] "
    read confirmation
    if [[ $confirmation = y ]]; then
      return 0
    elif [[ $confirmation = n || ! $confirmation ]]; then
      return 1
    fi
  done
}
