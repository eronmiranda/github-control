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
    curl -i --silent \
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
  set_gh_uri "$path" || die "Failed to form GH uri from: '${path}'"
  uri="$GH_URI"
  log "patch_gh: uri: ${uri}"
  log "patch_gh: data: ${data}"
  curl --silent \
    -XPATCH \
    -H "Authorization: token ${GH_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "${uri}" \
    --data-binary "$data"
}

put_gh() {
  assert_gh_access_token
  local path="$1"
  local data="$2"
  local uri
  set_gh_uri "$path" || die "Failed to form GH uri from: '${path}'"
  uri="$GH_URI"
  log "put_gh: uri: ${uri}"
  log "put_gh: data: ${data}"
  curl --silent \
    -XPUT \
    -H "Authorization: token ${GH_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    "$uri" \
    --data-binary "$data"
}

delete_gh() {
  assert_gh_access_token
  local path=${1:-}
  local uri
  local response_code
  set_gh_uri "$path" || die "Failed to form GH uri from: '${path}'"
  uri="$GH_URI"
  log "delete_gh: uri: ${uri}"
  response_code=$(curl -o /dev/null -I -w "%{http_code}" --silent \
              -XDELETE \
              -H "Authorization: token ${GH_ACCESS_TOKEN}" \
              -H "Content-Type: application/json" \
              -H "Accept: application/json" \
              "$uri")
  log "Status: ${response_code}"
  if ! { [ "$response_code" -ge 200 ] && [ "$response_code" -lt 300 ]; } then
    return 1
  fi 
}

set_url_path() {
  local option=${1:-}
  local path_parameter=${2:-}
  case $option in
      --user)
        [ -n "$path_parameter" ] || die "usage: ${ME} ${COMMAND} --user USER"
        URL_PATH="users/${path_parameter}/repos"
        ;;
      --auth-user)
        URL_PATH="user/repos?type=owner"
        ;;
      *)
        help
        die "Invalid options was provided: $option"
        ;;
  esac
}

cmd_get_repos() {
  set_url_path "$@"
  url_path="$URL_PATH"
  if ! repos="$(get_gh "$url_path")"; then
    die "failed to get repos"
  fi
  if ! jq --slurp -e 'all(type == "array")' <<< "$repos" > /dev/null; then
    die "error getting repos: $repos"
  fi
  echo "${repos}" | jq '.[]'
}

[ -n "${1:-}" ] || die "show all commands using: ${ME} help"
COMMAND="$1"
shift

case "$COMMAND" in
  help)
    help
    exit 0
    ;;
  get)
    [ -n "${1:-}" ] || die "usage: ${ME} ${COMMAND} PATH"
    get_gh "$1" | jq .
    ;;
  get-repo)
    { [ -n "${1:-}" ]; } || die "usage: ${ME} ${COMMAND} OWNER/REPO"
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
    auth_user=$(get_gh 'user' | jq -r '.login')
    if [ -z "$auth_user" ]; then
      die "failed to get authenticated user"
    fi
    if [ "$#" -eq 0 ]; then
      die "usage: ${ME} ${COMMAND} REPO [REPO...]"
    fi
    for r in "$@"; do
      log "make-repos-private: ${r}"
      patch_gh "repos/${auth_user}/${r}" '{"private": true}' | jq .
    done
    ;;
  make-repos-public)
    auth_user=$(get_gh 'user' | jq -r '.login')
    if [ -z "$auth_user" ]; then
      die "failed to get authenticated user"
    fi
    if [ "$#" -eq 0 ]; then
      die "usage: ${ME} ${COMMAND} REPO [REPO...]"
    fi
    for r in "$@"; do
      log "make-repos-public: ${r}"
      patch_gh "repos/${auth_user}/${r}" '{"private": false}' | jq .
    done
    ;;
  *)
    die "${COMMAND}: no such command"
    ;;
esac
