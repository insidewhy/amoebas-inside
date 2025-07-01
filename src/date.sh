iso_date_to_unix_date() {
  if [[ $OSTYPE = darwin* ]]; then
    date -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s
  else
    date -d "$1" +%s
  fi
}

unix_date_far_in_the_future() {
  if [[ $OSTYPE = darwin* ]]; then
    date -v+100y +%s
  else
    date -d 'now + 100 years' +%s
  fi
}
