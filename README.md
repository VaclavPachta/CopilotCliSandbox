# Copilot CLI Sandbox

Run GitHub Copilot CLI inside a Docker container, with auth and config persisted on your machine and shared across all sessions.

## How it works

```
~/.copilot-sandbox/               ← COPILOT_SANDBOX_BASE_PATH (default)
├── .copilot/                     ← Shared Copilot config (auth, skills, agents)
│   └── config.json               ←   mounted as ~/.copilot inside every container
├── Dockerfile                    ← Used to build / rebuild the image
├── MyProject/                    ← Session working directory
│   └── ...your files...
└── AnotherProject/               ← Another session
```

- **Auth** is stored once in `.copilot/config.json` and shared across all sessions.
- **Skills and agents** you install inside a session are persisted the same way.
- **Session folders** are the working directory Copilot sees inside the container.
- The Docker container is **ephemeral** — removed on exit. All state lives on disk.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (with WSL2 backend on Windows)
- PowerShell 6+

## Installation

Clone this repo and run the installer from PowerShell:

```powershell
git clone https://github.com/<your-username>/copilot-cli-sandbox
cd copilot-cli-sandbox
.\install.ps1
```

Then reload your profile:

```powershell
. $PROFILE
```

The installer:
1. Creates `~/.copilot-sandbox/` (or the path in `$env:COPILOT_SANDBOX_BASE_PATH`)
2. Copies the `Dockerfile` there
3. Builds the `copilot-sandbox` Docker image
4. Adds the `copilot-sandbox` function to your `$PROFILE`

### Custom base path

```powershell
.\install.ps1 -BasePath D:\MySandboxes
```

Or set the environment variable before running:

```powershell
$env:COPILOT_SANDBOX_BASE_PATH = "D:\MySandboxes"
.\install.ps1
```

## Usage

`copilot-sandbox.ps1` can be run **directly without installing** to your profile:

```powershell
# Run directly from the repo (no install needed)
.\copilot-sandbox.ps1 MyProject
.\copilot-sandbox.ps1 -Update
```

After running `install.ps1`, it's also available as a global command from any terminal:

```powershell
# Start a session (positional or named)
copilot-sandbox MyProject
copilot-sandbox -Session MyProject

# Start a session AND open the session folder in VS Code
copilot-sandbox MyProject -Code

# Update the Docker image to the latest Copilot CLI version
copilot-sandbox -Update
```

The first time you start a session you will be prompted to authenticate with `/login` inside the Copilot CLI. After that, auth is persisted in the shared `.copilot/` folder.

## What's inside the image

| Tool | Purpose |
|---|---|
| `node:22-slim` base | Debian Bookworm + Node.js 22 (required for Copilot CLI) |
| `git` | Clone repos, commit, branch, etc. |
| `curl` + `wget` | HTTP requests, downloading files |
| `python3` + `pip` | Run Python scripts Copilot generates |
| `jq` | JSON processing in shell scripts |
| `unzip` + `zip` | Archive handling |
| .NET SDK 8, 9, 10 | Build and run .NET projects |
| `csharp-ls` | C# Language Server for Copilot LSP integration |
| `@github/copilot` | The Copilot CLI itself |

## VS Code integration

Since the session folder (`COPILOT_SANDBOX_BASE_PATH/MyProject/`) is a host-mounted volume, you can open it directly in VS Code — no Docker extension needed:

```powershell
# Open manually
code $env:COPILOT_SANDBOX_BASE_PATH\MyProject

# Or use the built-in flag (opens VS Code + starts the session in one command)
copilot-sandbox MyProject -Code
```

The `-Code` flag calls `code <session-path>` before launching the container. VS Code opens the folder live — any files Copilot creates or modifies inside the container appear instantly.

## Authentication

Inside the container, GitHub Copilot CLI stores credentials in `~/.copilot/config.json` (the Linux keychain fallback for headless containers). This file is mounted from `<BasePath>/.copilot/`, so it persists across sessions and container restarts.

You can also pre-supply a token via environment variable — set `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, or `GITHUB_TOKEN` on the host before running `copilot-sandbox`, and the container will inherit it automatically.

## Changing the base path

Set `COPILOT_SANDBOX_BASE_PATH` in your environment (e.g. in `$PROFILE` or system settings) and the `copilot-sandbox` command will use it automatically at runtime — no reinstall needed:

```powershell
$env:COPILOT_SANDBOX_BASE_PATH = "D:\MySandboxes"
copilot-sandbox MyProject
```

## Updating to a new Copilot CLI version

```powershell
copilot-sandbox -Update
```

This rebuilds the Docker image from scratch (`docker build --no-cache`) so it picks up the latest `@github/copilot` npm package.

## Reinstalling

Re-running `install.ps1` is safe — it replaces the function in `$PROFILE` and rebuilds the image.

## C# Language Server (LSP)

The Docker image includes [`csharp-ls`](https://github.com/razzmatazz/csharp-language-server), a lightweight Roslyn-based C# Language Server. Copilot CLI uses it to provide enhanced code intelligence (go-to-definition, hover, diagnostics) for `.cs` files.

`install.ps1` automatically creates `~/.copilot-sandbox/.copilot/lsp-config.json` with the C# server configured:

```json
{
  "lspServers": {
    "csharp": {
      "command": "csharp-ls",
      "args": [],
      "fileExtensions": {
        ".cs": "csharp"
      }
    }
  }
}
```

Inside a session, use the `/lsp` command to check whether the C# language server is active. To add other language servers (e.g. TypeScript), edit `lsp-config.json` directly and add entries alongside `csharp`.
