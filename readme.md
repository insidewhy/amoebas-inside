# amoebas-inside

This project contains some very useful general purpose and devops related bash utilities:

- `aws.sh` - utilities for dealing with `aws-cli` and `aws-vault`
- `bparseopts.sh` - a modified but similar version of [zparseopts](https://man.archlinux.org/man/zshmodules.1.en#zparseopts) which works for bash
- `date.sh` - date utilities that work on both mac and linux
- `pnpm.sh` - get package paths/versions from their names in pnpm workspaces
- `prompt.sh` - prompt for a question until `y` is given, an empty line or `n` are treated as no
- `selector.sh` - provide a set of options to choose via a fuzzy selector, currently chooses the first installed selector from the following list:
  - `fzu`
  - `fzy`
  - `fzf`
  - `peco`
  - `selecta`
- `terraform.sh` - utilities for dealing with `terraform`
- `util.sh` - require for bash, like `source` but only if the script has not been sourced before, also provides `require_root` which will require relative to the recursively reachable parent directory from the current path that contains `.git`

A brief example of how these can be combined is shown below:

```bash
run_get_caller_identity() {
  # e.g. if the script is run like `script.sh -s -n boblar` then the variable $environment will
  # be set to the string "staging" and $name will be set to "boblar"
  bparseopts \
    e:=environment d=environment=dev s=environment=staging p=environment=production n:=name \
    -- "$@"

  # require the aws.sh utility library from this project, this script relies on the $environment
  # variable containing either "staging" or "production" so that the utility functions it provides
  # such as run_aws and run_vault can target the appropriate environment
  require_lib aws.sh

  # use one of the utilities provided by aws.sh
  local aws_account_id=$(run_aws sts get-caller-identity --query Account --output text)
  echo "Hi $name, your account id is $aws_account_id"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -e
  source "$(dirname $0)/../../lib/scripting/util.sh"
  run_get_caller_identity
fi
```
