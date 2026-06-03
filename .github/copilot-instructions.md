# Copilot Instructions

## Architecture

Four files make up the entire project:

| File | Role |
|---|---|
| `Dockerfile` | Container image definition. Base: `node:22-slim`. Optional features gated by `ARG INSTALL_<FEATURE>=false`. |
| `install.ps1` | One-time setup: copies files to `~/.copilot-sandbox/`, builds the image, injects `copilot-sandbox` function into `$PROFILE`. |
| `copilot-sandbox.ps1` | Runtime entry point: starts sessions, handles `-Update`/`-Add`/`-Remove` to rebuild the image. Copied to `~/.copilot-sandbox/` by the installer. |
| `README.md` | User-facing docs. Must stay in sync with scripts — every feature appears in both tables. |

### Runtime layout (on the user's machine)

```
~/.copilot-sandbox/
├── .copilot/
│   ├── config.json          ← Copilot auth (persisted across sessions)
│   ├── sandbox-config.json  ← Saved feature flags (used by -Update)
│   ├── settings.json        ← statusLine config
│   └── lsp-config.json      ← Created only when csharpls is enabled
├── Dockerfile               ← Copied here by install.ps1
├── copilot-sandbox.ps1      ← Copied here by install.ps1
└── <SessionName>/           ← Mounted as /workspace inside the container
```

## Adding an Optional Feature

Every new feature requires **parallel changes in four files**. The skill at `.github/skills/add-sandbox-feature/SKILL.md` has the full checklist.

### 1. `Dockerfile`

Add `ARG` to the existing ARG list, then add a conditional `RUN` block in the optional features section (before the "always installed" block):

```dockerfile
ARG INSTALL_<UPPER>=false
RUN if [ "$INSTALL_<UPPER>" = "true" ]; then \
      <install commands>; \
    fi
```

### 2. `install.ps1` — 7 locations

- `.PARAMETER Add` doc block
- `$validFeatures` array
- `$feat` hashtable init
- `all` expansion block
- Feature labels block (`$featureLabels`)
- `$buildArgs` block
- `$sandboxConfig` features block

### 3. `copilot-sandbox.ps1` — 9 locations

Same as `install.ps1`, plus:

- `.PARAMETER Remove` doc block
- `$feat` load from `sandbox-config.json`
- `Get-FeatureSet` `all` branch
- Legacy fallback `$feat` (`else` branch when no config file)
- Save merged config back block

### 4. `README.md` — 2 tables

- Optional features table under `### Optional features`
- "What's inside the image" table

## Key Conventions

**Docker build uses stdin, not build context.** Both scripts pipe the Dockerfile via stdin:
```powershell
Get-Content $dockerfilePath | docker @buildArgs  # last element of $buildArgs is '-'
```
Never switch to `docker build .` — this avoids uploading `~/.copilot-sandbox/` (which contains session data and credentials) as build context.

**Feature naming:** CLI names are lowercase (`playwright`, `rtk`). The `$feat` hashtable uses camelCase keys (`csharpLs` not `csharpls`). Pure lowercase names need no mapping. Names like `csharpls` that become camelCase need an explicit `if ($item -eq 'csharpls') { 'csharpLs' } else { $item }` mapping in **both** scripts.

**`$feat` must stay in sync** across `install.ps1`, `copilot-sandbox.ps1`, and the `sandbox-config.json` keys. A key present in one script but missing from the `sandbox-config.json` load in the other will silently drop that feature on `-Update`.

**`all` expansion must be exhaustive.** Both scripts have a hardcoded list of all feature names inside the `all` branch. Update both when adding a feature.

**`-Update` uses `--no-cache`; initial build does not.** The `-Update` path in `copilot-sandbox.ps1` always passes `--no-cache` to pick up the latest npm packages. The first-run auto-build and `install.ps1` build do not.

**`csharpls` implies dotnet.** If `csharpls` is enabled without any dotnet SDK, both scripts automatically enable `dotnet10`. This guard must be replicated when adding features with similar implicit dependencies.

**`$PROFILE` injection is idempotent.** The installer uses `# BEGIN copilot-sandbox` / `# END copilot-sandbox` markers to replace the block on re-runs. The injected function is a thin wrapper that delegates to `copilot-sandbox.ps1` in `~/.copilot-sandbox/` — all logic stays in the script file, not in the profile block.
