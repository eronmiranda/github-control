#!/bin/bash
#
# validation.sh - Input validation functions for gh-control
#

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

check_repo_exists() {
  local owner="$1"
  local repo="$2"
  
  log "Checking if repository exists: ${owner}/${repo}"
  if ! get_gh "repos/${owner}/${repo}" >/dev/null 2>&1; then
    die "Repository not found: ${owner}/${repo}"
  fi
}
