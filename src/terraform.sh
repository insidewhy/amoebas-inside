# util.sh must have been required/sourced before using any functions in this file

terraform_get_root() {
  # assumes this is being called from a subdirectory (e.g. "scripts") of a directory containing
  # terraform configuration where environments are found in an environments subdirectory
  echo "$(dirname "${BASH_SOURCE[2]}")/../environments/$environment"
}

terraform_apply_aws() {
  # This assumes the directory containing `environments` is in the directory above the script that
  # calls this function
  require_lib bparseopts.sh
  bparseopts P=plan \
    e:=environment s=environment=staging p=environment=production d=environment=dev -- "$@"

  if [[ $plan ]]; then
    vault_type=plan
  fi
  require_lib aws.sh
  require_lib date.sh

  local credential_expiration="$(run_vault printenv AWS_CREDENTIAL_EXPIRATION)"
  local key_remaining_time=$[$(iso_date_to_unix_date "$credential_expiration") - $(date +%s)]

  # refuse to apply if the credentials will expire in less than 30 minutes
  if (( $key_remaining_time < 1800 )); then
    fail "credentials will expire in $key_remaining_time seconds, refusing to apply"
  fi

  subcmd=apply
  if [[ $plan ]]; then
    subcmd=plan
  fi

  local environment_root="$(terraform_get_root)"
  run_vault terraform -chdir="$environment_root" $subcmd
}

create_terraform_state_aws() {
  require_lib bparseopts.sh

  bparseopts \
    e:=environment s=environment=staging p=environment=production d=environment=dev \
    -- "$@"

  local prefix="${positionals[0]}"
  if [[ ! $prefix ]]; then
    fail "Must provide s3 bucket prefix as positional argument"
  fi

  require_lib aws.sh
  local region="$(get_aws_region)"

  bucket_name=$prefix-terraform-state-$environment

  run_aws s3api create-bucket \
    --bucket $bucket_name \
    --region $region \
    --create-bucket-configuration LocationConstraint=$region

  run_aws s3api put-bucket-versioning \
    --bucket $bucket_name \
    --versioning-configuration Status=Enabled

  run_aws dynamodb create-table \
    --region $region \
    --table-name terraform-lock-table \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
}

terraform_suggest_moves() {
  require_lib bparseopts.sh
  bparseopts \
    e:=environment s=environment=staging p=environment=production d=environment=dev n=no_confirm \
    -- "$@"

  require_lib aws.sh

  local environment_root="$(terraform_get_root)"

  IFS=$(echo -en "\n\b")
  output=($(
    run_vault terraform -chdir="$environment_root" plan -no-color \
      | grep '^ *# .*will be' | grep -Ev 'read during apply|updated in-place' \
      | sed -e 's/ *# *//g' -e 's/\(.*\) will be \(.*\)/\2 \1/'
  ))
  IFS=

  local destroys=()
  local creates=()
  for line in "${output[@]}"; do
    if [[ $line == destroyed* ]]; then
      destroys+=(${line#destroyed })
    elif [[ $line = created* ]]; then
      creates+=(${line#created })
    else
      fail "bad line: $line"
    fi
  done

  if (( ${#destroys[@]} != ${#creates[@]} )); then
    fail "destructions and creations are not the same size"
  fi

  if [[ ${#destroys[@]} = 0 ]]; then
    warn "there are no changes to make"
  else
    local params="-e $environment"
    if [[ $no_confirm ]]; then
      params+=" -n"
    fi

    for ((i = 0; i < ${#creates[@]}; i++)); do
      echo "./scripts/move-state.sh $params \\"
      echo "  '${destroys[$i]}' \\"
      echo "  '${creates[$i]}'"
    done
  fi
}

terraform_move_state() {
  require_lib bparseopts.sh
  bparseopts e:=environment s=environment=staging p=environment=production d=environment=dev n=no_confirm -- "$@"

  require_lib aws.sh
  require_lib prompt.sh

  local environment_root="$(terraform_get_root)"
  pushd_silent "$environment_root"
    for ((i=0; $i <${#positionals[@]}; i+=2)); do
      from="${positionals[$i]}"
      to="${positionals[$i + 1]}"

      if [[ $no_confirm ]]; then
        run_vault terraform state mv "$from" "$to"
      else
        if confirm "Move\n$from\n$to\n"; then
          run_vault terraform state mv "$from" "$to"
        else
          echo skipping
        fi
      fi
    done
  popd_silent
}

terraform_apply_replace() {
  local replace_args=()
  for arg in "$@"; do
    replace_args+=(-replace $arg)
  done

  run_vault terraform apply "${replace_args[@]}"
}

terraform_replace_resource() {
  require_lib bparseopts.sh
  bparseopts e:=environment s=environment=staging p=environment=production d=environment=dev n=no_confirm -- "$@"
  local to_replace="${positionals[@]}"

  require_lib aws.sh
  require_lib selector.sh

  local environment_root="$(terraform_get_root)"
  pushd_silent "$environment_root"
    if [[ ! $to_replace ]]; then
      local to_replace="$(run_vault terraform state list | selector)"
    fi

    if [[ ! $to_replace ]]; then
      return
    fi

    if [[ $no_confirm ]]; then
      terraform_apply_replace ${to_replace[@]}
    else
      require_lib prompt.sh
      if confirm "Replace ${to_replace[@]} "; then
        terraform_apply_replace ${to_replace[@]}
      fi
    fi
  popd_silent
}

terraform_list_state() {
  require_lib bparseopts.sh
  bparseopts e:=environment s=environment=staging p=environment=production d=environment=dev \
    e:=ends_with m:=match_regex r:=replace_with a=replace_args -- "$@"

  require_lib aws.sh

  local environment_root="$(terraform_get_root)"
  pushd_silent "$environment_root"
    local cmd=(run_vault terraform state list)
    local grep_expr

    if [[ $ends_with ]]; then
      if [[ $match_regex ]]; then
        fail "cannot use -m and -e arguments together"
      fi

      grep_expr="$ends_with$"
      replace_from="$ends_with"
    elif [[ $match_regex ]]; then
      grep_expr="$match_regex"
      replace_from="$grep_expr"
    fi

    if [[ $grep_expr ]]; then
      if [[ $replace_with ]]; then
        local sed_expression="s&$replace_from&{\0,$replace_with}&"
        if [[ $replace_args ]]; then
          states=($(${cmd[@]} | grep "$grep_expr"))
          result=()
          for state in "${states[@]}"; do
            echo -n $(echo "${state}" | sed 's&\("\|\[\|\]\)&\\\0&g') | sed "$sed_expression"
            echo -n " "
          done
          echo
        else
          ${cmd[@]} | grep "$grep_expr" | sed "$sed_expression"
        fi
      else
        ${cmd[@]} | grep "$grep_expr"
      fi
    else
      ${cmd[@]}
    fi
  popd_silent
}
