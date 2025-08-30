#!/bin/bash
#
# logging.sh - Logging utilities for gh-control
#

LOG_ME=${ME%.sh}

log() {
  >&2 echo "${LOG_ME}: $(gdate --utc +%H:%M:%SZ): $*"
}

die() {
  log "$@"
  exit 1
}
