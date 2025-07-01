# TODO: only do this when AWS_ACCESS_KEY_ID is not set, otherwise grab using awscli
: ${environment:=dev}

vault_cmd=(env)
if [[ ! $AWS_ACCESS_KEY_ID ]]; then
  if [[ $vault_type ]]; then
    vault_cmd=(aws-vault exec $environment-$vault_type)
  else
    vault_cmd=(aws-vault exec $environment)
  fi
fi

run_vault() {
  if [[ $1 = -s ]]; then
    shift
    ${vault_cmd[@]} &>/dev/null -- "$@"
  else
    ${vault_cmd[@]} -- "$@"
  fi
}

run_aws() {
  run_vault aws "$@"
}

get_aws_region() {
  run_vault printenv AWS_REGION
}

get_aws_secret() {
  run_aws --output text secretsmanager \
    get-secret-value --query SecretString --secret-id $1
}

get_aws_secret_from_list() {
  # util.sh must have been required/sourced before using this function
  require_lib bparseopts.sh
  bparseopts e:=environment s=environment=staging p=environment=production d=environment=dev -- "$@"

  local secret="${positionals[0]}"

  if [[ ! $secret ]]; then
    require_lib selector.sh

    secret="$(
      run_aws secretsmanager --output text list-secrets \
        --query 'SecretList[].Name' | tr '\t' '\n' \
        | selector
    )"

    if [[ ! $secret ]]; then
      fail "must select a secret"
    fi
  fi

  get_aws_secret "$secret"
}

aws_logs() {
  # util.sh must have been required/sourced before using this function
  require_lib bparseopts.sh
  bparseopts e:=environment s=environment=staging p=environment=production d=environment=dev \
    l=live S:=since F=no_follow -- "$@"

  local log_group="${positionals[0]}"

  if [[ ! $log_group ]]; then
    require_lib selector.sh
    log_group="$(
      run_aws --output text logs describe-log-groups --query 'logGroups[].logGroupName' \
      | tr '\t' '\n' \
      | selector
    )"
    if [[ ! $log_group ]]; then
      fail "must select a log group"
    fi
  fi

  if [[ $live ]]; then
    local arn=$(
      run_aws logs describe-log-groups \
        | jq -r ".logGroups[] | select(.logGroupName == \"$log_group\") | .logGroupArn"
    )

    if [ -z "$arn" ]; then
      fail could not find log group $log_group
    fi

    run_aws logs start-live-tail --log-group-identifier $arn
  else
    local tail_args=()
    if [[ $since ]]; then
      tail_args+=(--since $since)
    fi
    local log_group_args=()
    # if stdout is a terminal and -F wasn't used then follow the logs
    if [[ -t 1 && ! $no_follow ]]; then
      tail_args+=(--follow)
    fi

    run_aws logs tail --format json "${tail_args[@]}" $log_group
  fi
}

aws_reload_ecs_task() {
  # util.sh must have been required/sourced before using this function
  require_lib bparseopts.sh
  bparseopts e:=environment s=environment=staging p=environment=production d=environment=dev -- "$@"

  local clusters=($(run_aws --output text ecs list-clusters --query 'clusterArns'))

  declare -A task_to_cluster
  local tasks=()
  for cluster in "${clusters[@]}"; do
    local cluster_tasks=(
      $(run_aws --output text ecs list-services --cluster=$cluster --query serviceArns)
    )

    for task in "${cluster_tasks[@]}"; do
      task=${task##*service/}
      tasks+=($task)
      task_to_cluster[$task]=$cluster
    done
  done

  local to_restart="${positionals[0]}"
  if [[ ! $to_restart ]]; then
    require_lib selector.sh
    to_restart=$(selector "${tasks[@]}")

    if [[ ! $to_restart ]]; then
      fail "must select a task to restart"
    fi
  fi

  local cluster=${task_to_cluster[$to_restart]}

  echo restarting service $to_restart in cluster $cluster
  run_aws --no-cli-pager ecs update-service --cluster "$cluster" --service "$to_restart" --force-new-deployment

  echo waiting for service to restart
  run_aws ecs wait services-stable --cluster $cluster --service $to_restart
}

# get user pool id given name of user pool
aws_get_user_pool_id() {
  run_aws cognito-idp list-user-pools --output text --max-results 10 \
    --query "UserPools[?Name=='$1'].Id"
}

# get user pool client by name of user pool for user pool that contains only one client
aws_get_user_pool_client_id() {
  local user_pool_id=$(aws_get_user_pool_id $1)
  run_aws cognito-idp list-user-pool-clients --output text \
    --user-pool-id $user_pool_id --query='UserPoolClients[].ClientId'
}

aws_get_user_pool_client_auth_token() {
  require_lib bparseopts.sh
  bparseopts c:=user_pool_client_id u:=username p:=password t:=token_path -- "$@"
  : ${token_path:=AccessToken}

  local region=$(get_aws_region)

  curl -s --location --request POST "https://cognito-idp.$region.amazonaws.com" \
    --header 'X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth' \
    --header 'Content-Type: application/x-amz-json-1.1' \
    --data-raw '{
       "AuthParameters" : {
          "USERNAME" : "'$username'",
          "PASSWORD" : "'$password'"
       },
       "AuthFlow" : "USER_PASSWORD_AUTH",
       "ClientId" : "'$user_pool_client_id'"
    }' | jq -r .AuthenticationResult.$token_path
}
