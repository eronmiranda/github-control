# GitHub Repository Control Tool

A robust, modular command-line tool for managing GitHub repositories through the GitHub API. Built with safety, reliability, and ease of use in mind.

## ✨ Features

### Core Functionality

- 📋 List repositories (all, public, private, or archived)
- 🔍 Get detailed repository information
- 🔒 Change repository visibility (public/private) with safety checks
- 👤 Support for both authenticated user and specific user repositories
- 📄 Pagination support for large repository lists

### Safety & Reliability

- 🧪 **Dry-run mode** - Preview changes before applying them
- ✅ **Confirmation prompts** - Prevent accidental bulk operations
- 🛡️ **Input validation** - Comprehensive validation of all inputs
- 🔐 **Ownership verification** - Ensures you own repositories before modifying them
- ⚡ **Rate limit management** - Intelligent API rate limiting
- 🚨 **Enhanced error handling** - Clear, actionable error messages

### Developer Experience

- 📦 **Modular architecture** - Clean, maintainable codebase
- 🔧 **Multiple configuration options** - Environment variables, config files
- 📊 **Progress tracking** - See success/failure counts for bulk operations
- 🐛 **Debug mode** - Raw API access for troubleshooting

## 📋 Prerequisites

- `bash` (4.0 or later)
- `jq` for JSON processing
- `curl` for API requests
- `gdate` (GNU date) for timestamp handling
- GitHub Personal Access Token with appropriate permissions

## 🚀 Quick Start

### Installation

1. **Clone the repository:**

   ```bash
   git clone https://github.com/yourusername/gh-control.git
   cd gh-control
   ```

2. **Make the script executable:**

   ```bash
   chmod +x gh-control.sh
   ```

3. **Set up authentication** (choose one method):

   **Method 1: Environment Variable (Recommended)**

   ```bash
   export GH_ACCESS_TOKEN="your_token_here"
   ```

   **Method 2: Configuration File**

   ```bash
   cp config.example .env
   # Edit .env and add your token
   ```

   **Method 3: Legacy Token File**

   ```bash
   echo 'GH_ACCESS_TOKEN="your_token_here"' > .github_token
   chmod 600 .github_token
   ```

### First Run

```bash
# Test the installation
./gh-control.sh help

# Try a safe command
./gh-control.sh get-repos --user octocat
```

## 💡 Usage

### Basic Commands

```bash
# Show help (no authentication required)
./gh-control.sh help

# List all repositories for a user
./gh-control.sh get-repos --user octocat

# List your private repositories
./gh-control.sh get-private-repos --auth-user

# Get details of a specific repository
./gh-control.sh get-repo octocat/Hello-World
```

### Safety Features

```bash
# Preview changes before applying (dry-run mode)
DRY_RUN=true ./gh-control.sh make-repos-private repo1 repo2

# Skip confirmation prompts (for automation)
FORCE=true ./gh-control.sh make-repos-public repo1 repo2

# Combine both for testing automation scripts
DRY_RUN=true FORCE=true ./gh-control.sh make-repos-private repo1 repo2
```

### Repository Management

```bash
# Make repositories private (with confirmation)
./gh-control.sh make-repos-private repo1 repo2

# Make repositories public (with confirmation)
./gh-control.sh make-repos-public repo1 repo2
```

## 📖 Command Reference

### Information Commands

| Command               | Description                                   | Authentication Required |
| --------------------- | --------------------------------------------- | ----------------------- |
| `help`                | Show help message and exit                    | ❌ No                   |
| `get {PATH\|URL}`     | Make HTTP GET request to API endpoint (debug) | ✅ Yes                  |
| `get-repo OWNER/REPO` | Get details of a specific repository          | ✅ Yes                  |

### Repository Listing

| Command              | Description                     | Options                        |
| -------------------- | ------------------------------- | ------------------------------ |
| `get-repos`          | List all repositories           | `--user USER` or `--auth-user` |
| `get-public-repos`   | List public repositories only   | `--user USER` or `--auth-user` |
| `get-private-repos`  | List private repositories only  | `--user USER` or `--auth-user` |
| `get-archived-repos` | List archived repositories only | `--user USER` or `--auth-user` |

### Repository Management

| Command                      | Description               | Safety Features                         |
| ---------------------------- | ------------------------- | --------------------------------------- |
| `make-repos-private REPO...` | Make repositories private | ✅ Ownership check, confirmation prompt |
| `make-repos-public REPO...`  | Make repositories public  | ✅ Ownership check, confirmation prompt |

### Options

- `--user USER` - List repositories for specified user
- `--auth-user` - List repositories for authenticated user

### Global Environment Variables

- `DRY_RUN=true` - Show what would be done without making changes
- `FORCE=true` - Skip confirmation prompts for destructive operations
- `KEEP_TMP=y` - Preserve temporary files for debugging

## 🔐 Authentication

### GitHub Personal Access Token

The tool requires a GitHub Personal Access Token with the following permissions:

| Permission | Required For          | Description                                            |
| ---------- | --------------------- | ------------------------------------------------------ |
| `repo`     | Repository management | Full control of private repositories                   |
| `read:org` | Organization repos    | Read organization data (if accessing org repositories) |

### Token Setup

1. **Create a token** at [GitHub Settings > Developer settings > Personal access tokens](https://github.com/settings/tokens)
2. **Select scopes** based on your needs (see table above)
3. **Configure the tool** using one of the authentication methods above

## 🏗️ Architecture

The tool is built with a modular architecture for maintainability and extensibility:

```
gh-control/
├── gh-control.sh          # Main script and command dispatcher
├── lib/                   # Modular library components
│   ├── logging.sh         # Logging utilities
│   ├── config.sh          # Configuration management
│   ├── validation.sh      # Input validation functions
│   ├── github-api.sh      # GitHub API interactions
│   ├── safety.sh          # Safety features (dry-run, confirmations)
│   └── commands.sh        # Command implementations
├── config.example         # Example configuration file
└── README.md             # This file
```

## 🔒 Security Best Practices

### Token Security

- ❌ **Never commit your GitHub token** to version control
- 🔐 **Use environment variables** for production deployments
- 📁 **Secure file permissions** (`chmod 600`) for token files
- 🔄 **Rotate tokens regularly** and revoke unused ones
- 🎯 **Use minimum required permissions** for your token

### Safe Operations

- 🧪 **Always test with dry-run** before bulk operations
- ✅ **Review confirmation prompts** carefully
- 👤 **Verify repository ownership** before making changes
- 📊 **Monitor API rate limits** to avoid service disruption

## 🐛 Troubleshooting

### Common Issues

**"Failed to parse API response status"**

- Usually indicates network connectivity issues
- Check your internet connection and GitHub API status

**"Authentication error: Bad credentials"**

- Verify your GitHub token is correct and not expired
- Ensure the token has the required permissions

**"Rate limit exceeded"**

- Wait for the rate limit to reset (usually 1 hour)
- Consider using a token with higher rate limits

**"Repository not found"**

- Check the repository name spelling
- Verify you have access to the repository
- Ensure the repository exists

### Debug Mode

Enable debug information:

```bash
KEEP_TMP=y ./gh-control.sh your-command
# Check the temporary directory for API response details
```

---

**Built with ☕️ by [@eronmiranda](https://github.com/eronmiranda)**

_A robust, safety-first approach to GitHub repository management._
