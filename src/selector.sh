SELECTOR_OPTIONS=(fzu fzy fzf peco selecta)

function selector() {
  if [[ ! $SELECTOR ]]; then
    for option in $SELECTOR_OPTIONS; do
      if which >/dev/null $option; then
        SELECTOR=$option
        break
      fi
    done
  fi

  if [[ $# = 0 ]]; then
    $SELECTOR
  else
    for opt in "$@"; do echo $opt; done | $SELECTOR
  fi
}
