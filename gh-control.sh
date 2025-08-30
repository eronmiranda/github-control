#!/bin/bash
#
# gh-control - GitHub management tool
# Version: 1.1.0
# Author: Eronielle Miranda

set -o errexit
set -o nounset
set -o pipefail 

ME=$(basename "$0")
LOG_ME=${ME%.sh}

# load library modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logging.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/validation.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/github-api.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/safety.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/commands.sh"

shopt -s extglob

help() {
  cat <<EOF
usage: ${ME} COMMAND [OPTIONS]

Description:
  This tool interacts with the Github API to automate tasks on Github.

Authentication:
  Requires a Github access token for authentication. 
  Your environment must contain:
    GH_ACCESS_TOKEN="your_token_here"

Commands:
  Information Commands:
    help                            Show this help message and exit
    get {PATH|URL}                  Make HTTP GET request to API endpoint (debug only)
    get-repo OWNER/REPO             Get details of a specific repository

  Repository Listing:
    get-repos         {OPTIONS}     List all repositories
    get-public-repos  {OPTIONS}     List public repositories
    get-private-repos {OPTIONS}     List private repositories
    get-archived-repos {OPTIONS}    List archived repositories

  Repository Visibility:
    make-repos-private REPO...      Make specified repositories private
    make-repos-public  REPO...      Make specified repositories public

Options:
  For repository listing commands:
    --user USER                     List repositories for the specified user
    --auth-user                     List repositories for the authenticated user

  Global options (set as environment variables):
    DRY_RUN=true                    Show what would be done without making changes
    FORCE=true                      Skip confirmation prompts for destructive operations

Examples:
  ${ME} get-repo octocat/Hello-World
  ${ME} get-repos --user octocat
  ${ME} get-private-repos --auth-user
  ${ME} make-repos-private myrepo1 myrepo2

Notes:
  - All commands require authentication via GH_ACCESS_TOKEN
  - Repository names for visibility changes must belong to authenticated user
EOF
}

init_config

[ -n "${1:-}" ] || die "show all commands using: ${ME} help"
COMMAND="$1"
shift

case "$COMMAND" in
  help)
    help
    exit 0
    ;;
  get)
    show_config_info
    check_rate_limit
    [ -n "${1:-}" ] || die "usage: ${ME} ${COMMAND} PATH"
    validate_path_parameter "$1"
    get_gh "$1" | jq .
    ;;
  get-repo)
    show_config_info
    check_rate_limit
    { [ -n "${1:-}" ]; } || die "usage: ${ME} ${COMMAND} OWNER/REPO"
    validate_owner_repo "$1"
    log "get-repo: getting '${1}'"
    get_gh "repos/${1}" | jq .
    ;;
  get-repos)
    show_config_info
    check_rate_limit
    cmd_get_repos "$@"
    ;;
  get-public-repos)
    show_config_info
    check_rate_limit
    cmd_get_repos "$@" | jq '. | select(.private == false)'
    ;;
  get-private-repos)
    show_config_info
    check_rate_limit
    cmd_get_repos "$@" | jq '. | select(.private == true)'
    ;;
  get-archived-repos)
    show_config_info
    check_rate_limit
    cmd_get_repos "$@" | jq '. | select(.archived == true)'
    ;;
  make-repos-private)
    show_config_info
    check_rate_limit
    cmd_make_repos_private "$@"
    ;;
  make-repos-public)
    show_config_info
    check_rate_limit
    cmd_make_repos_public "$@"
    ;;
  *)
    die "${COMMAND}: no such command"
    ;;
esac
