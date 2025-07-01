pnpm_package_path() {
  project="$1"
  if [[ ! $project ]]; then
    fail Must supply project name as positional argument
  fi
  pnpm ls -r --json | jq -r ".[] | select(.name == \"$project\") | .path"
}

pnpm_package_version() {
  project_path=$(pnpm_package_path "$1")
  cat $project_path/package.json | jq -r '.version'
}
