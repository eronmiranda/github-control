#!/bin/bash
#
# safety.sh - Safety and confirmation functions for gh-control
#

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
