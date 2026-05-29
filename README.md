# Copilot CLI Sandbox

Run GitHub Copilot CLI inside a Docker container, with auth and config persisted on your machine and shared across all sessions.

## How it works

```
~/.copilot-sandbox/               ← COPILOT_SANDBOX_BASE_PATH (default)
├── .copilot/                     ← Shared Copilot config (auth, skills, agents)
│   └── config.json               ←   mounted as ~/.copilot inside every container
├── Dockerfile                    ← Used to build / rebuild the image
├── MyProject/                    ← Named session working directory
│   └── ...your files...
└── AnotherProject/               ← Another named session
```

Named sessions always live under the base path. You can also mount **any existing directory** directly using `-Path` (or the `.` shorthand for the current directory).

- **Auth** is stored once in `.copilot/config.json` and shared across all sessions.
- **Skills and agents** you install inside a session are persisted the same way.
- **Session folders** live under the base path. Use `-Path` (or `.`) to mount any existing directory instead.
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

### Optional features

By default, `install.ps1` builds a lean base image with only the Copilot CLI and core tools. Use `-Add` to include optional components:

| Feature name | What it installs |
|---|---|
| `playwright` | Playwright CLI + Chromium browser |
| `csharpls` | C# Language Server (`csharp-ls`) |
| `dotnet8` | .NET SDK 8 |
| `dotnet9` | .NET SDK 9 |
| `dotnet10` | .NET SDK 10 |
| `all` | All of the above |

```powershell
# Lean base image (Copilot CLI + core tools only)
.\install.ps1

# Add Playwright and C# LSP (auto-includes .NET 10)
.\install.ps1 -Add playwright,csharpls

# Install everything
.\install.ps1 -Add all

# Mix and match
.\install.ps1 -Add dotnet9,playwright
```

> **Note:** `csharpls` requires a .NET SDK. If no dotnet feature is included, `.NET 10` is enabled automatically.

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
# Named session
.\copilot-sandbox.ps1 MyProject
# Mount current directory
.\copilot-sandbox.ps1 .
# Mount an explicit path
.\copilot-sandbox.ps1 -Path C:\temp\MyProject
.\copilot-sandbox.ps1 -Update
```

After running `install.ps1`, it's also available as a global command from any terminal:

```powershell
# Named session (created in base path if it doesn't exist)
copilot-sandbox MyProject
copilot-sandbox -Session MyProject

# Mount the current directory
copilot-sandbox .

# Mount any existing directory (relative or absolute)
copilot-sandbox -Path ./my-repo
copilot-sandbox -Path C:\Users\me\Projects\MyApp

# Start a session AND open the session folder in VS Code
copilot-sandbox MyProject -Code
copilot-sandbox . -Code

# Start a session AND open the session folder in JetBrains Rider
copilot-sandbox MyProject -Rider
copilot-sandbox . -Rider

# Open in both VS Code and Rider simultaneously
copilot-sandbox MyProject -Code -Rider

# Update the Docker image to the latest Copilot CLI version (reuses saved feature config)
copilot-sandbox -Update

# Add a feature at update time (merged + saved for future updates)
copilot-sandbox -Update -Add playwright

# Remove a feature at update time (saved for future updates)
copilot-sandbox -Update -Remove dotnet8

# Add and remove in the same call
copilot-sandbox -Update -Add csharpls -Remove playwright
```

The first time you start a session you will be prompted to authenticate with `/login` inside the Copilot CLI. After that, auth is persisted in the shared `.copilot/` folder.

## What's inside the image

| Tool | Purpose | Optional |
|---|---|---|
| `node:22-slim` base | Debian Bookworm + Node.js 22 (required for Copilot CLI) | — |
| `git` | Clone repos, commit, branch, etc. | — |
| `curl` + `wget` | HTTP requests, downloading files | — |
| `python3` + `pip` | Run Python scripts Copilot generates | — |
| `jq` | JSON processing in shell scripts | — |
| `unzip` + `zip` | Archive handling | — |
| `@github/copilot` | The Copilot CLI itself | — |
| .NET SDK 8 | Build and run .NET 8 projects | `-Add dotnet8` |
| .NET SDK 9 | Build and run .NET 9 projects | `-Add dotnet9` |
| .NET SDK 10 | Build and run .NET 10 projects | `-Add dotnet10` |
| `csharp-ls` | C# Language Server for Copilot LSP integration | `-Add csharpls` |
| `@playwright/test` + Chromium | End-to-end testing with the Playwright CLI (`npx playwright`) | `-Add playwright` |

## VS Code integration

Since the session folder (`COPILOT_SANDBOX_BASE_PATH/MyProject/`) is a host-mounted volume, you can open it directly in VS Code — no Docker extension needed:

```powershell
# Open a named session folder manually
code $env:COPILOT_SANDBOX_BASE_PATH\MyProject

# Or use the built-in flag (opens VS Code + starts the session in one command)
copilot-sandbox MyProject -Code

# Works with -Path too
copilot-sandbox . -Code
copilot-sandbox -Path C:\temp\MyProject -Code
```

The `-Code` flag calls `code <session-path>` before launching the container. VS Code opens the folder live — any files Copilot creates or modifies inside the container appear instantly.

## JetBrains Rider integration

The `-Rider` flag works the same way as `-Code`, but opens the session folder in JetBrains Rider instead:

```powershell
# Open a named session folder in Rider
copilot-sandbox MyProject -Rider

# Works with -Path too
copilot-sandbox . -Rider
copilot-sandbox -Path C:\temp\MyProject -Rider
```

Rider is launched via the `rider` shell command. Enable it in **JetBrains Toolbox → Settings → Generate shell scripts**. `-Rider` and `-Code` can be combined to open both editors at once.

## Session name in the status line

Every session automatically shows its name (e.g. `📁 MyProject`) in the Copilot CLI status line at the bottom of the screen. This is wired up by `install.ps1`, which:

1. Creates `~/.copilot-sandbox/.copilot/statusline-session.sh` — a small script that reads the `COPILOT_SANDBOX_SESSION` environment variable and prints the decorated name.
2. Adds a `statusLine` entry to `~/.copilot-sandbox/.copilot/settings.json` pointing at that script.

The session name is passed into the container via `-e COPILOT_SANDBOX_SESSION=<name>` on `docker run`, so no image rebuild is required. If you start a container manually (without `copilot-sandbox`), the status line item is simply blank.

## Authentication

Inside the container, GitHub Copilot CLI stores credentials in `~/.copilot/config.json` (the Linux keychain fallback for headless containers). This file is mounted from `<BasePath>/.copilot/`, so it persists across sessions and container restarts.

You can also pre-supply a GitHub PAT via the `COPILOT_SANDBOX_GITHUB_TOKEN` environment variable on your host. When set, `copilot-sandbox` passes it into the container as `COPILOT_GITHUB_TOKEN` (the env var the Copilot CLI reads for token-based auth):

```powershell
$env:COPILOT_SANDBOX_GITHUB_TOKEN = "<your-github-pat>"
copilot-sandbox MyProject
```

Add the `$env:COPILOT_SANDBOX_GITHUB_TOKEN = ...` line to your `$PROFILE` to make it permanent. The token is optional — if not set, the container falls back to the credential file in `.copilot/config.json`.

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

This rebuilds the Docker image from scratch (`docker build --no-cache`) so it picks up the latest `@github/copilot` npm package. The feature set from your original `install.ps1` run is saved to `.copilot/sandbox-config.json` and replayed automatically.

Use `-Add` or `-Remove` alongside `-Update` to adjust the feature set. Changes are saved back to the config for all future updates:

```powershell
# Add a feature (saved for future -Update calls)
copilot-sandbox -Update -Add playwright

# Remove a feature (saved for future -Update calls)
copilot-sandbox -Update -Remove playwright

# Add and remove in one call
copilot-sandbox -Update -Add csharpls -Remove dotnet8

# Add everything
copilot-sandbox -Update -Add all

# Remove everything (lean base)
copilot-sandbox -Update -Remove all
```

## Reinstalling

Re-running `install.ps1` is safe — it replaces the function in `$PROFILE` and rebuilds the image.

## C# Language Server (LSP)

The [`csharp-ls`](https://github.com/razzmatazz/csharp-language-server) language server is an **optional feature** installed with `-Add csharpls`. It provides enhanced code intelligence (go-to-definition, hover, diagnostics) for `.cs` files.

```powershell
.\install.ps1 -Add csharpls
```

When `-CsharpLs` is used, `install.ps1` automatically creates `~/.copilot-sandbox/.copilot/lsp-config.json`:

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
