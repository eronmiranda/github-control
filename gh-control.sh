#!/bin/bash
#
# gh-control - GitHub management tool
# Version: 1.0.0
# Author: Eronielle Miranda

set -o errexit
set -o nounset
set -o pipefail 

ME=$(basename "$0")
LOG_ME=${ME%.sh}

DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}

# shellcheck disable=SC1091
. ".github_token"

log() {
  >&2 echo "${LOG_ME}: $(gdate --utc +%H:%M:%SZ): $*"
}

die() {
  log "$@"
  exit 1
}

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

if [ "${KEEP_TMP:-n}" == 'y' ]; then
  TMP=${LOG_ME}-$(gdate --utc +%Y-%m-%d-%H-%M-%SZ)
else
  TMP=$(mktemp -d)
  trap 'rm -rf "${TMP}"' EXIT
fi

mkdir -p "${TMP}"

log "using temporary directory: ${TMP}"

if [ "${KEEP_TMP:-n}" != 'y' ]; then
  log "will delete temporary directory on exit"
fi

assert_gh_access_token() {
  if [ -z "${GH_ACCESS_TOKEN:-}" ]; then
    die "environment must contain GH_ACCESS_TOKEN"
  fi
}

GH_HOST=api.github.com

shopt -s extglob

next_page_uri() {
  jq -r '
  .headers[] |
  select(test("^link:")) |
  capture("[<](?<uri>[^>]+)[>];[ ]*rel=\"next\"") |
  .uri
  ' "$1"
}

set_gh_uri() {
  local path="${1:-}"
  case "$path" in
    https*)
      GH_URI="$path"
      ;;
    *)
      GH_URI="https://${GH_HOST}/${path}"
      ;;
  esac
}  

check_api_response() {
  local response_file="$1"
  local status_code
  local error_message
  
  status_code=$(jq -r '.status' "$response_file" | grep -o '[0-9]\+' | head -1)
  
  if [ -z "$status_code" ]; then
    die "Failed to parse API response status"
  fi
  
  case "$status_code" in
    200|201|204)
      return 0
      ;;
    401)
      error_message=$(jq -r '.body.message // "Authentication failed"' "$response_file")
      die "Authentication error: $error_message. Check your GitHub token."
      ;;
    403)
      error_message=$(jq -r '.body.message // "Forbidden"' "$response_file")
      if echo "$error_message" | grep -q "rate limit"; then
        die "Rate limit exceeded: $error_message"
      else
        die "Permission denied: $error_message. Check token permissions."
      fi
      ;;
    404)
      error_message=$(jq -r '.body.message // "Not found"' "$response_file")
      die "Resource not found: $error_message"
      ;;
    422)
      error_message=$(jq -r '.body.message // "Validation failed"' "$response_file")
      die "Validation error: $error_message"
      ;;
    *)
      error_message=$(jq -r '.body.message // "Unknown error"' "$response_file")
      die "API error (HTTP $status_code): $error_message"
      ;;
  esac
}

get_gh() {
  assert_gh_access_token
  local path=${1##+(/)}
  local uri
  set_gh_uri "$path" || die "Failed to form GH uri from: '${path}'"
  uri="$GH_URI"
  local name
  local tmp=${TMP}/${name}
  name="get_gh_$(gdate +%s)"
  mkdir -p "${tmp}"
  log "get_gh: uri: ${uri}"
  local page=0
  local next_uri
  while true; do
    log "get_gh: uri: ${uri}"
    curl -i --silent --max-time 30 \
      -H "Authorization: token ${GH_ACCESS_TOKEN}" \
      -H "Accept: application/json" \
      "${uri}" 2> "${tmp}/${page}.stderr" |
    tee "${tmp}/${page}.stdout" |
    jq -R --slurp '
      def trim:
        sub("^[ \t]+";"") | sub("[ \t]+$";"");

      split("\r\n\r\n") |
      (
        .[0] |
        split("\r\n") |
        {
          status: (.[0] | trim),
          headers: [.[range(1;length)]]
        }
      ) +
      { body: (.[1] | . as $i | try fromjson catch $i) }
      ' > "${tmp}/${page}.stdout.json"
    
    if [ ! -s "${tmp}/${page}.stdout.json" ]; then
      die "Network error: Failed to connect to GitHub API"
    fi
    
    check_api_response "${tmp}/${page}.stdout.json"
    
    jq .body "${tmp}/${page}.stdout.json"
    next_uri="$(next_page_uri "${tmp}/${page}.stdout.json")"
    if [ -z "$next_uri" ]; then
      break
    fi
    uri="$next_uri"
    page=$((page + 1))
  done
}

patch_gh() {
  assert_gh_access_token
  local path=${1:-}
  local data=${2:-}
  local uri
  local tmp_response
  set_gh_uri "$path" || die "Failed to form GH uri from: '${path}'"
  uri="$GH_URI"
  tmp_response="${TMP}/patch_response_$(gdate +%s).json"
  
  log "patch_gh: uri: ${uri}"
  log "patch_gh: data: ${data}"
  
  curl -i --silent --max-time 30 \
    -XPATCH \
    -H "Authorization: token ${GH_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "${uri}" \
    --data-binary "$data" |
  jq -R --slurp '
    def trim:
      sub("^[ \t]+";"") | sub("[ \t]+$";"");

    split("\r\n\r\n") |
    (
      .[0] |
      split("\r\n") |
      {
        status: (.[0] | trim),
        headers: [.[range(1;length)]]
      }
    ) +
    { body: (.[1] | . as $i | try fromjson catch $i) }
    ' > "$tmp_response"
  
  if [ ! -s "$tmp_response" ]; then
    die "Network error: Failed to connect to GitHub API"
  fi
  
  check_api_response "$tmp_response"
  jq .body "$tmp_response"
}

put_gh() {
  assert_gh_access_token
  local path="$1"
  local data="$2"
  local uri
  local tmp_response
  set_gh_uri "$path" || die "Failed to form GH uri from: '${path}'"
  uri="$GH_URI"
  tmp_response="${TMP}/put_response_$(gdate +%s).json"
  
  log "put_gh: uri: ${uri}"
  log "put_gh: data: ${data}"
  
  curl -i --silent --max-time 30 \
    -XPUT \
    -H "Authorization: token ${GH_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "$uri" \
    --data-binary "$data" |
  jq -R --slurp '
    def trim:
      sub("^[ \t]+";"") | sub("[ \t]+$";"");

    split("\r\n\r\n") |
    (
      .[0] |
      split("\r\n") |
      {
        status: (.[0] | trim),
        headers: [.[range(1;length)]]
      }
    ) +
    { body: (.[1] | . as $i | try fromjson catch $i) }
    ' > "$tmp_response"
  
  if [ ! -s "$tmp_response" ]; then
    die "Network error: Failed to connect to GitHub API"
  fi
  
  check_api_response "$tmp_response"
  jq .body "$tmp_response"
}

delete_gh() {
  assert_gh_access_token
  local path=${1:-}
  local uri
  local tmp_response
  set_gh_uri "$path" || die "Failed to form GH uri from: '${path}'"
  uri="$GH_URI"
  tmp_response="${TMP}/delete_response_$(gdate +%s).json"
  
  log "delete_gh: uri: ${uri}"
  
  curl -i --silent --max-time 30 \
    -XDELETE \
    -H "Authorization: token ${GH_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "$uri" |
  jq -R --slurp '
    def trim:
      sub("^[ \t]+";"") | sub("[ \t]+$";"");

    split("\r\n\r\n") |
    (
      .[0] |
      split("\r\n") |
      {
        status: (.[0] | trim),
        headers: [.[range(1;length)]]
      }
    ) +
    { body: (.[1] | . as $i | try fromjson catch $i) }
    ' > "$tmp_response"
  
  if [ ! -s "$tmp_response" ]; then
    die "Network error: Failed to connect to GitHub API"
  fi
  
  check_api_response "$tmp_response"
}

set_url_path() {
  local option=${1:-}
  local path_parameter=${2:-}

  [ -n "$option" ] || die "No option provided"

  case $option in
      --user)
        [ -n "$path_parameter" ] || die "usage: ${ME} ${COMMAND} --user USER"
        validate_username "$path_parameter"
        URL_PATH="users/${path_parameter}/repos"
        ;;
      --auth-user)
        URL_PATH="user/repos?type=owner"
        ;;
      *)
        help
        die "Invalid option provided: $option"
        ;;
  esac
}

validate_repo_name() {
  local repo="$1"
  
  # GitHub repository names can contain alphanumeric characters, hyphens, underscores, and periods
  # They cannot start or end with hyphens, and cannot contain consecutive hyphens
  if [[ -z "$repo" ]]; then
    die "Repository name cannot be empty"
  fi
  
  if [[ ${#repo} -gt 100 ]]; then
    die "Repository name too long (max 100 characters): $repo"
  fi
  
  if [[ ! "$repo" =~ ^[A-Za-z0-9._-]+$ ]]; then
    die "Invalid repository name: $repo (only alphanumeric, dots, hyphens, and underscores allowed)"
  fi
  
  if [[ "$repo" =~ ^[-.]|[-.]$ ]]; then
    die "Invalid repository name: $repo (cannot start or end with hyphens or dots)"
  fi
  
  if [[ "$repo" =~ -- ]]; then
    die "Invalid repository name: $repo (cannot contain consecutive hyphens)"
  fi
}

validate_owner_repo() {
  local owner_repo="$1"
  
  if [[ -z "$owner_repo" ]]; then
    die "Owner/repository format required (e.g., 'owner/repo')"
  fi
  
  if [[ ! "$owner_repo" =~ ^[^/]+/[^/]+$ ]]; then
    die "Invalid format: $owner_repo (expected 'owner/repo')"
  fi
  
  local owner="${owner_repo%/*}"
  local repo="${owner_repo#*/}"
  
  validate_username "$owner"
  validate_repo_name "$repo"
}

validate_username() {
  local username="$1"
  
  if [[ -z "$username" ]]; then
    die "Username cannot be empty"
  fi
  
  if [[ ${#username} -gt 39 ]]; then
    die "Username too long (max 39 characters): $username"
  fi
  
  if [[ ! "$username" =~ ^[A-Za-z0-9-]+$ ]]; then
    die "Invalid username: $username (only alphanumeric and hyphens allowed)"
  fi
  
  if [[ "$username" =~ ^-|-$ ]]; then
    die "Invalid username: $username (cannot start or end with hyphens)"
  fi
  
  if [[ "$username" =~ -- ]]; then
    die "Invalid username: $username (cannot contain consecutive hyphens)"
  fi
}

validate_path_parameter() {
  local path="$1"
  
  if [[ -z "$path" ]]; then
    die "Path parameter cannot be empty"
  fi
  
  # remove any potentially dangerous characters
  if [[ "$path" =~ [[:space:]\;\&\|\`\$\(\)] ]]; then
    die "Invalid characters in path: $path"
  fi
}

confirm_action() {
  local action="$1"
  local repos=("${@:2}")
  
  if [[ "$FORCE" == "true" ]]; then
    return 0
  fi
  
  echo "WARNING: You are about to $action the following repositories:"
  printf "  - %s\n" "${repos[@]}"
  echo
  read -p "Are you sure you want to continue? (y/N): " -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Operation cancelled by user"
    exit 0
  fi
}

dry_run_message() {
  local action="$1"
  local repo="$2"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY RUN] Would $action repository: $repo"
    return 0
  fi
  return 1
}

check_repo_exists() {
  local owner="$1"
  local repo="$2"
  
  log "Checking if repository exists: ${owner}/${repo}"
  if ! get_gh "repos/${owner}/${repo}" >/dev/null 2>&1; then
    die "Repository not found: ${owner}/${repo}"
  fi
}

validate_repo_ownership() {
  local auth_user="$1"
  local repo="$2"
  
  log "Validating ownership of repository: ${auth_user}/${repo}"
  local repo_info
  if ! repo_info=$(get_gh "repos/${auth_user}/${repo}" 2>/dev/null); then
    die "Cannot access repository: ${auth_user}/${repo}. Check if it exists and you have permissions."
  fi
  
  local repo_owner
  repo_owner=$(echo "$repo_info" | jq -r '.owner.login')
  if [[ "$repo_owner" != "$auth_user" ]]; then
    die "You don't own repository: ${auth_user}/${repo} (owned by: $repo_owner)"
  fi
}

cmd_get_repos() {
  set_url_path "$@"
  url_path="$URL_PATH"
  
  log "Fetching repositories from: $url_path"
  
  local repos
  if ! repos="$(get_gh "$url_path" 2>/dev/null)"; then
    die "Failed to fetch repositories. Check your token permissions and network connection."
  fi
  
  if ! jq --slurp -e 'all(type == "array")' <<< "$repos" > /dev/null 2>&1; then
    die "Invalid response format from GitHub API. Response: $repos"
  fi
  
  echo "${repos}" | jq '.[]'
}

check_rate_limit() {
  local rate_limit
  rate_limit=$(get_gh "rate_limit" | jq .resources.core.remaining)
  if [ "$rate_limit" -lt 1 ]; then
    die "GitHub API rate limit exceeded. Please try again later."
  fi
}

[ -n "${1:-}" ] || die "show all commands using: ${ME} help"
COMMAND="$1"
shift

if [[ "$DRY_RUN" == "true" ]]; then
  log "Running in DRY RUN mode - no changes will be made"
fi

if [[ "$FORCE" == "true" ]]; then
  log "Running in FORCE mode - skipping confirmation prompts"
fi

check_rate_limit

case "$COMMAND" in
  help)
    help
    exit 0
    ;;
  get)
    [ -n "${1:-}" ] || die "usage: ${ME} ${COMMAND} PATH"
    validate_path_parameter "$1"
    get_gh "$1" | jq .
    ;;
  get-repo)
    { [ -n "${1:-}" ]; } || die "usage: ${ME} ${COMMAND} OWNER/REPO"
    validate_owner_repo "$1"
    log "get-repo: getting '${1}'"
    get_gh "repos/${1}" | jq .
    ;;
  get-repos)
    cmd_get_repos "$@"
    ;;
  get-public-repos)
    cmd_get_repos "$@" | jq '. | select(.private == false)'
    ;;
  get-private-repos)
    cmd_get_repos "$@" | jq '. | select(.private == true)'
    ;;
  get-archived-repos)
    cmd_get_repos "$@" | jq '. | select(.archived == true)'
    ;;
  make-repos-private)
    if [ "$#" -eq 0 ]; then
      die "usage: ${ME} ${COMMAND} REPO [REPO...]"
    fi
    
    for r in "$@"; do
      validate_repo_name "$r"
    done
    
    log "Getting authenticated user information..."
    auth_user=$(get_gh 'user' 2>/dev/null | jq -r '.login')
    if [ -z "$auth_user" ] || [ "$auth_user" = "null" ]; then
      die "Failed to get authenticated user. Check your GitHub token."
    fi
    log "Authenticated as: $auth_user"
    
    for r in "$@"; do
      validate_repo_ownership "$auth_user" "$r"
    done
    
    confirm_action "make private" "$@"
    
    success_count=0
    total_count=$#
    
    for r in "$@"; do
      if dry_run_message "make private" "${auth_user}/${r}"; then
        continue
      fi
      
      log "Making repository private: ${auth_user}/${r}"
      if patch_gh "repos/${auth_user}/${r}" '{"private": true}' >/dev/null 2>&1; then
        log "Successfully made ${r} private"
        ((success_count++))
      else
        log "Failed to make ${r} private, continuing with next repository..."
      fi
    done
    
    if [[ "$DRY_RUN" != "true" ]]; then
      log "Completed: ${success_count}/${total_count} repositories made private"
    fi
    ;;
  make-repos-public)
    if [ "$#" -eq 0 ]; then
      die "usage: ${ME} ${COMMAND} REPO [REPO...]"
    fi
    
    for r in "$@"; do
      validate_repo_name "$r"
    done
    
    log "Getting authenticated user information..."
    auth_user=$(get_gh 'user' 2>/dev/null | jq -r '.login')
    if [ -z "$auth_user" ] || [ "$auth_user" = "null" ]; then
      die "Failed to get authenticated user. Check your GitHub token."
    fi
    log "Authenticated as: $auth_user"
    
    for r in "$@"; do
      validate_repo_ownership "$auth_user" "$r"
    done
    
    confirm_action "make public" "$@"
    
    success_count=0
    total_count=$#
    
    for r in "$@"; do
      if dry_run_message "make public" "${auth_user}/${r}"; then
        continue
      fi
      
      log "Making repository public: ${auth_user}/${r}"
      if patch_gh "repos/${auth_user}/${r}" '{"private": false}' >/dev/null 2>&1; then
        log "Successfully made ${r} public"
        ((success_count++))
      else
        log "Failed to make ${r} public, continuing with next repository..."
      fi
    done
    
    if [[ "$DRY_RUN" != "true" ]]; then
      log "Completed: ${success_count}/${total_count} repositories made public"
    fi
    ;;
  *)
    die "${COMMAND}: no such command"
    ;;
esac
