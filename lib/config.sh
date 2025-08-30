#!/bin/bash
#
# config.sh - Configuration management for gh-control
#

load_github_token() {
  # Priority order: environment variable, .github_token file, .env file
  if [[ -n "${GH_ACCESS_TOKEN:-}" ]]; then
    log "Using GitHub token from environment variable"
    return 0
  fi
  
  if [[ -f ".github_token" ]]; then
    log "Loading GitHub token from .github_token file"
    # shellcheck disable=SC1091
    source ".github_token"
    return 0
  fi
  
  if [[ -f ".env" ]]; then
    log "Loading configuration from .env file"
    # shellcheck disable=SC1091
    source ".env"
    return 0
  fi
  
  die "No GitHub token found. Set GH_ACCESS_TOKEN environment variable or create .github_token file"
}

init_config() {
  # Global flags with defaults
  DRY_RUN=${DRY_RUN:-false}
  FORCE=${FORCE:-false}
  KEEP_TMP=${KEEP_TMP:-n}
  
  load_github_token
  
  if [ "$KEEP_TMP" == 'y' ]; then
    TMP=${LOG_ME}-$(gdate --utc +%Y-%m-%d-%H-%M-%SZ)
  else
    TMP=$(mktemp -d)
    trap 'rm -rf "${TMP}"' EXIT
  fi
  
  mkdir -p "${TMP}"
  log "using temporary directory: ${TMP}"
  
  if [ "$KEEP_TMP" != 'y' ]; then
    log "will delete temporary directory on exit"
  fi
}

show_config_info() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "Running in DRY RUN mode - no changes will be made"
  fi
  
  if [[ "$FORCE" == "true" ]]; then
    log "Running in FORCE mode - skipping confirmation prompts"
  fi
}
