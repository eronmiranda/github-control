#!/bin/bash
#
# commands.sh - Command implementations for gh-control
#

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

cmd_make_repos_private() {
  if [ "$#" -eq 0 ]; then
    die "usage: ${ME} make-repos-private REPO [REPO...]"
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
  
  # Process repositories
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
}

cmd_make_repos_public() {
  if [ "$#" -eq 0 ]; then
    die "usage: ${ME} make-repos-public REPO [REPO...]"
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
}
