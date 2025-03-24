#!/bin/bash

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

options_usage='
    where:
      --user USER   List information of the specified user.
      --auth-user   List information of the authenticated user.
'

help() {
  cat <<EOF
usage: ${ME} COMMAND [OPTIONS]

where COMMAND is one of

  help
    Print this message

  get {PATH|URL}
    Call the API at PATH (or URL) using HTTP GET request. Use only 
    for debugging and experimentation purposes.

  get-repo OWNER/REPO
    Get the details of a single repository named REPO and owned by
    OWNER. OWNER can be either an organization or a user.

  get-repos {--user USER | --auth-user}
    List repositories of the specified option.${options_usage}

  get-public-repos {--user USER | --auth-user}
    List public repositories of the specified option.${options_usage}

  get-private-repos {--user USER | --auth-user}
    List private repositories of the specified option.${options_usage}

  get-archived-repos {--user USER | --auth-user}
    List archived repositories of the specified option.${options_usage}

  make-repo-private
    Make one or more repositories public.

  make-repo-private
    Make one or more repositories private.

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
    for r in "$@"; do
      patch_gh "repos/${r}" '{"private": true}' | jq .
    done
    ;;
  make-repos-public)
    for r in "$@"; do
      patch_gh "repos/${r}" '{"private": false}' | jq .
    done
    ;;
  *)
    die "${COMMAND}: no such command"
    ;;
esac
