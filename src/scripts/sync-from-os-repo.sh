#!/bin/bash

cleanup_sync_from_os_repo() {
  if [ -d "$AMOEBAS_INSIDE_TEMP_DIR" ]; then
    rm -rf "$AMOEBAS_INSIDE_TEMP_DIR"
    log_info "Cleaned up temporary directory"
  fi
}

sync_from_os_repo() {
  trap cleanup_sync_from_os_repo EXIT

  local repo_url="https://github.com/insidewhy/amoebas-inside.git"
  AMOEBAS_INSIDE_TEMP_DIR=$(mktemp -d)
  local target_dir="$(dirname "${BASH_SOURCE[1]}")/.."

  log_info "Starting sync of scripting library from $repo_url"

  log_info "Cloning repository to temporary directory..."
  if ! git clone --depth 1 "$repo_url" "$AMOEBAS_INSIDE_TEMP_DIR"; then
    fail "Failed to clone repository"
  fi

  if [ ! -d "$AMOEBAS_INSIDE_TEMP_DIR/src" ]; then
    fail "Source directory 'src' not found in repository"
  fi

  log_info "Copying files from open source repository to $target_dir"
  cp $AMOEBAS_INSIDE_TEMP_DIR/src/*.sh "$target_dir"
  mkdir -p "$target_dir/scripts"
  cp $AMOEBAS_INSIDE_TEMP_DIR/src/scripts/*.sh "$target_dir/scripts"
  cp $AMOEBAS_INSIDE_TEMP_DIR/readme.md "$target_dir"

  log_info "Successfully synced scripting library"
  log_info "Files synchronized:"
  ls -lA "$target_dir"
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  set -e
  source "$(dirname $0)/../util.sh"
  sync_from_os_repo "$@"
fi
