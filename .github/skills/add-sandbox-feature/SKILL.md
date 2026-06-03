---
name: add-sandbox-feature
description: "Guides adding a new optional feature to the Copilot CLI Sandbox repo. Updates all four required locations: Dockerfile, install.ps1, copilot-sandbox.ps1, and README.md. Use when the user wants to add a new optional tool, SDK, or package that can be toggled via -Add at install time."
---

# Add Sandbox Feature

A new optional feature requires **identical, parallel changes in four files**. Work through each section in order.

## 1. Collect feature details

**If the user provides a URL** (docs, GitHub repo, etc.), fetch it with the `web_fetch` tool before asking any questions. Use the page to determine:
- the recommended install method (apt, npm, curl-pipe-sh, binary download, etc.)
- the correct binary/package name
- any post-install steps (PATH export, config file, etc.)

Then confirm or fill in the remaining details:

- **Feature name** — lowercase CLI name (e.g. `python312`). Pure lowercase needs no special mapping.
- **`ARG` name** — uppercase with `INSTALL_` prefix (e.g. `INSTALL_PYTHON312`).
- **`$feat` key** — camelCase if the CLI name would produce one (e.g. `csharpls` → `csharpLs`); otherwise same as CLI name.
- **Docker install commands** — the `apt-get`, `npm`, `curl`, etc. commands inferred from the docs (base image is `node:22-slim` / Debian Bookworm).
- **README description** — one-line description for the features table.
- **Any post-install setup?** — e.g. `csharpls` creates `lsp-config.json`. Note it now.

---

## 2. `Dockerfile`

Add an `ARG` + conditional `RUN` block in the **Optional features** section (before the "always installed" block):

```dockerfile
# ---------------------------------------------------------------------------
# <Description> (optional: --build-arg INSTALL_<UPPER>=true)
# ---------------------------------------------------------------------------
ARG INSTALL_<UPPER>=false
RUN if [ "$INSTALL_<UPPER>" = "true" ]; then \
      <install commands>; \
    fi
```

Also add the `ARG` declaration to the existing ARG list near the top of the optional section.

---

## 3. `install.ps1` — 7 locations

### 3a. `.PARAMETER Add` doc block
```powershell
      <name>     — <description>
```

### 3b. `$validFeatures` array
```powershell
$validFeatures = @('playwright','csharpls',...,'<name>','all')
```

### 3c. `$feat` hashtable initialisation
```powershell
$feat = @{ ...; <key>=$false }
```

### 3d. `all` expansion block
```powershell
$feat['<key>']=$true
```

### 3e. Feature labels block
```powershell
if ($feat['<key>']) { $featureLabels += '<Display Name>' }
```

### 3f. `$buildArgs` block
```powershell
if ($feat['<key>']) { $buildArgs += '--build-arg', 'INSTALL_<UPPER>=true' }
```

### 3g. `$sandboxConfig` features block
```powershell
$sandboxConfig = [ordered]@{
    features = [ordered]@{
        ...
        <key> = $feat['<key>']
    }
}
```

---

## 4. `copilot-sandbox.ps1` — 9 locations

### 4a. `.PARAMETER Add` doc block — same as install.ps1 3a
### 4b. `.PARAMETER Remove` doc block — add the name to the valid values list
### 4c. `$validFeatures` array — same as install.ps1 3b
### 4d. Load from `sandbox-config.json`
```powershell
$feat = @{
    ...
    <key> = [bool]$f.<key>
}
```
### 4e. Legacy fallback `$feat` (the `else` branch with no config file)
```powershell
$feat = @{ ...; <key>=$false }
```
### 4f. `Get-FeatureSet` `all` branch
```powershell
foreach ($k in @('playwright','csharpls',...,'<name>')) { $set[$k] = $true }
```
### 4g. Feature labels block — same as install.ps1 3e
### 4h. `$buildArgs` block — same as install.ps1 3f
### 4i. Save merged config back — same as install.ps1 3g

---

## 5. `README.md` — 2 tables

### 5a. Optional features table (under `### Optional features`)
```md
| `<name>` | <description> |
```

### 5b. "What's inside the image" table
```md
| `<tool>` | <purpose> | `-Add <name>` |
```

---

## 6. Checklist

- [ ] `ARG INSTALL_<UPPER>=false` added to Dockerfile ARG list
- [ ] Dockerfile `RUN` block added
- [ ] `install.ps1`: `$validFeatures`, `$feat`, `all`, labels, buildArgs, sandboxConfig
- [ ] `copilot-sandbox.ps1`: both doc blocks, `$validFeatures`, `$feat` load + legacy, `Get-FeatureSet all`, labels, buildArgs, save config
- [ ] README: optional features table + "What's inside" table
- [ ] CLI name → `$feat` key mapping: if name is `csharpls`-style (needs camelCase), add explicit mapping `if ($item -eq '<name>') { '<key>' } else { $item }` in both scripts
- [ ] If post-install setup is needed (e.g. config file creation), add to `install.ps1` with the same `if ($feat['<key>'])` guard used by `csharpls`

---

## Key conventions

- **Build uses stdin, not context**: both scripts pipe Dockerfile via stdin (`Get-Content $dockerfilePath | docker @buildArgs`). Never switch to a path-based `docker build .`.
- **`$feat` must stay in sync** between both scripts and `sandbox-config.json` keys.
- **`all` list must be exhaustive** in both scripts.
- **camelCase mapping**: CLI names that are purely lowercase (e.g. `playwright`, `rtk`) need no special mapping. Names like `csharpls` that map to `csharpLs` need an explicit `if` in the `-eq 'csharpls'` style.
