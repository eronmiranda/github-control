# GitHub Repository Control Tool

A command-line tool for managing GitHub repositories through the GitHub API. This tool allows you to list, modify, and manage repository visibility settings with ease.

## Features

- List repositories (all, public, private, or archived)
- Get repository details
- Change repository visibility (public/private)
- Support for both authenticated user and specific user repositories
- Pagination support for large repository lists
- Temporary file handling for API responses
- Debug mode with raw API access

## Prerequisites

- `bash` (4.0 or later)
- `jq` for JSON processing
- `curl` for API requests
- `gdate` (GNU date) for timestamp handling
- GitHub Personal Access Token

## Installation

1. Clone the repository:

    ```bash
    git clone https://github.com/yourusername/gh-control.git
    cd gh-control
    ```

2. Make the script executable:

    ```bash
    chmod +x gh-control.sh
    ```

3. Set up your GitHub token:

    ```bash
    echo 'GH_ACCESS_TOKEN="your_token_here"' > .github_token
    chmod 600 .github_token
    ```

Alternatively, you can use your favorite code editor to add the access token directly to the `.github_token` file. This approach helps prevent the token from being exposed in your shell history.

## Usage

### Basic Commands

```bash
# Show help
./gh-control.sh help

# List all repositories for a user
./gh-control.sh get-repos --user eron

# List your private repositories
./gh-control.sh get-private-repos --auth-user

# Make repositories private
./gh-control.sh make-repos-private repo1 repo2

# Make repositories public
./gh-control.sh make-repos-public repo1 repo2
```

### Command Reference

Information Commands:

- `help` - Show help message
- `get {PATH|URL}` - Make HTTP GET request to API endpoint (debug)
- `get-repo OWNER/REPO` - Get repository details

Repository Listing:

- `get-repos {OPTIONS}` - List all repositories
- `get-public-repos {OPTIONS}` - List public repositories
- `get-private-repos {OPTIONS}` - List private repositories
- `get-archived-repos {OPTIONS}` - List archived repositories

Repository Visibility:

- `make-repos-private REPO...` - Make repositories private
- `make-repos-public REPO...` - Make repositories public

Options

- `--user USER` - List repositories for specified user
- `--auth-user` - List repositories for authenticated user

## Authentication

The tool requires a GitHub Personal Access Token for authentication. The token should have the following permissions:

- `repo` - Full control of private repositories
- `read:org` - Read organization data (if accessing organization repositories)

## Environment Variables

- `GH_ACCESS_TOKEN` - Your GitHub Personal Access Token
- `KEEP_TMP` - Set to 'y' to preserve temporary files (default: 'n')

## Error Handling

The script includes comprehensive error handling:

- Validates required environment variables
- Checks for required command-line arguments
- Verifies API response status codes
- Provides detailed error messages

## Security

- Never commit your GitHub token
- Keep your `.github_token` file secure with appropriate permissions
- Regularly rotate your GitHub Personal Access Token
- Use the minimum required permissions for your token
