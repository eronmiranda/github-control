# GitHub control tool

## WIP

## Prerequisites

 You must have:

- `jq` installed
- Generated a GitHub token that has the right permissions

## Setting up Environment Variables Locally

This project requires an environment variable to be set on your local machine. Follow the instructions below to securely add and use the environment variable.

### 1. Create a `.env` or `.github_token` File

In the root directory of this project, create a `.env` file. This file will store your environment variable securely.

**Example `.env` file:**

```bash
GH_ACCESS_TOKEN="your_token_here"
```

Replace `your_token_here` with the actual value of your GitHub token.

### 2. Set Permissions for the `.env` File

To ensure that your `.env` file is secure and readably only by you, set the correct permissions:

```bash
chmod 600 .env
```

This will restrict access to the file to only your user account.

### 3. Add .env to .gitignore

To ensure that the `.env` file is not tracked by Git and doesn't get committed, add it to your `.gitignore` file:

1. Open or create the `.gitignore` file in the root directory of this project.
2. Add `.env` to the file:

    ```bash
    .env
    ```

This will prevent the `.env` file from being accidentally pushed to version control.
