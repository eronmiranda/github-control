# Library Modules

This directory contains modular components for the gh-control tool:

## Modules

- **logging.sh** - Logging utilities and error handling
- **config.sh** - Configuration management and initialization
- **validation.sh** - Input validation functions
- **github-api.sh** - GitHub API interaction functions
- **safety.sh** - Safety features (dry-run, confirmations)
- **commands.sh** - Command implementations

## Usage

These modules are automatically loaded by the main `gh-control.sh` script. They can also be sourced individually for testing or reuse in other scripts.

## Dependencies

All modules depend on:

- bash 4.0+
- jq (JSON processor)
- curl (HTTP client)
- gdate (GNU date command)
