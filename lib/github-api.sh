#!/bin/bash
#
# github-api.sh - GitHub API interaction functions
#

GH_HOST=api.github.com

assert_gh_access_token() {
  if [ -z "${GH_ACCESS_TOKEN:-}" ]; then
    die "environment must contain GH_ACCESS_TOKEN"
  fi
}

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
  
  status_code=$(jq -r '.status' "$response_file" | grep -o '[0-9]\{3\}' | head -1)
  
  if [ -z "$status_code" ] || [ "$status_code" = "null" ]; then
    log "Debug: Raw status from response: $(jq -r '.status' "$response_file")"
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

check_rate_limit() {
  local rate_limit
  rate_limit=$(get_gh "rate_limit" | jq .resources.core.remaining)
  if [ "$rate_limit" -lt 1 ]; then
    die "GitHub API rate limit exceeded. Please try again later."
  fi
}
