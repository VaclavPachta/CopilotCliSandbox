# Copilot CLI Sandbox — 5-Minute Demo Script
**Format:** Pre-recorded screencast  
**Audience:** Fellow developers / engineers  
**Total target runtime:** ~5 minutes

---

## Timeline

| Time | Section | What happens on screen |
|---|---|---|
| 0:00 – 0:20 | Intro | Short title card or narration: "GitHub Copilot CLI Sandbox — isolated, persistent, Docker-based AI coding sessions" |
| 0:20 – 0:50 | Clone & install | `git clone`, then `.\install.ps1 -Add dotnet8,dotnet10,csharpls` |
| 0:50 – 1:30 | Docker build (sped up) | Timelapse/speedup of the build output; show full build passing at the end |
| 1:30 – 1:50 | Auth slide-in | Briefly show auth options; no live login needed |
| 1:50 – 2:10 | Reload profile + launch session | `. $PROFILE` → `copilot-sandbox FibonacciDemo -Code` |
| 2:10 – 2:25 | VS Code + container open | VS Code pops open; terminal shows Copilot CLI prompt with `📁 FibonacciDemo` status bar |
| 2:25 – 5:00 | Money shot | Ask Copilot to implement Fibonacci in C# using TDD; show tests + implementation generated |

---

## Full Narration Script

### 0:00 – 0:20 · Intro

> "This is the Copilot CLI Sandbox — a way to run GitHub Copilot CLI inside a Docker container,  
> with your auth and config persisted on your machine and shared across every session.  
> All you need is Docker Desktop and PowerShell 6+."

**Screen:** Show `docker --version` and `$PSVersionTable.PSVersion` briefly.

---

### 0:20 – 0:50 · Clone & Install

**Type on screen:**
```powershell
git clone https://github.com/VaclavPachta/CopilotCliSandbox
cd CopilotCliSandbox
.\install.ps1 -Add dotnet8,dotnet10,csharpls
```

> "We clone the repo and run the installer. The `-Add` flag lets us bake in optional features —  
> here we're adding .NET 8, .NET 10, and the C# Language Server for code intelligence."

**Callout on screen:** `csharpls` auto-enables dotnet10 if no SDK is specified — here we're adding both explicitly.

---

### 0:50 – 1:30 · Docker Build (speed-up)

> "The installer builds a Docker image. This takes a few minutes the first time —  
> we're speeding this up."

**Screen:** Timelapse of `docker build` output. End on:
```
✓ Image 'copilot-sandbox' built successfully.
```

> "After that, the `copilot-sandbox` command is registered in your PowerShell profile."

---

### 1:30 – 1:50 · Auth

> "Auth is handled once. You have two options:"

**Screen:** Split / two bullet callout:

**Option A — Interactive login (first run inside container):**
```
/login
```
> "Run `/login` inside any session the first time. Credentials are saved to `~/.copilot-sandbox/.copilot/config.json` and shared across all future sessions automatically."

**Option B — GitHub PAT (CI-friendly / pre-authenticated):**
```powershell
$env:COPILOT_SANDBOX_GITHUB_TOKEN = "<your-pat>"
# Add to $PROFILE for persistence
```
> "Or set a GitHub Personal Access Token. Get one at:  
> **github.com → Settings → Developer settings → Personal access tokens**  
> Scope needed: `read:user` (Copilot uses OAuth under the hood)."

**Screen:** Briefly flash `github.com/settings/tokens` URL.

> "For this demo, we're pre-authenticated — the credential file already exists."

---

### 1:50 – 2:10 · Reload Profile & Launch Session

**Type on screen:**
```powershell
. $PROFILE
copilot-sandbox FibonacciDemo -Code
```

> "Reload the profile to activate the command, then launch a named session.  
> The `-Code` flag opens the session folder in VS Code at the same time."

---

### 2:10 – 2:25 · VS Code + Container Start

**Screen:** VS Code window opens with an empty `FibonacciDemo/` folder.  
Terminal shows the Copilot CLI REPL with `📁 FibonacciDemo` in the status bar.

> "VS Code is watching the folder live — any file Copilot creates inside the container  
> appears here instantly. No Docker extension, no remote SSH."

---

### 2:25 – 5:00 · Money Shot — TDD Fibonacci in C#

**Type in the Copilot CLI session:**
```
Create a new .NET solution with a class library project and an xUnit test project.
Then implement the Fibonacci sequence in C# using a TDD approach:
write the failing tests first, then implement the function to make them pass.
```

> "Let's ask Copilot to do something real — implement Fibonacci in C# with TDD."

**Screen shows (in sequence):**
1. Copilot creates `FibonacciDemo.sln`, `FibonacciLib/`, `FibonacciTests/`
2. Generates `FibonacciTests/FibonacciTests.cs` with `[Fact]` tests for edge cases (0, 1, n)
3. Generates `FibonacciLib/Fibonacci.cs` with the implementation
4. VS Code sidebar updates live as files appear
5. (Optional) `dotnet test` run inside the container showing all tests passing

> "Files appear in VS Code instantly as Copilot creates them.  
> When it's done, we run the tests — all green."

**End card / narration:**
> "That's the Copilot CLI Sandbox.  
> Isolated. Persistent. One command to spin up.  
> `copilot-sandbox -Update` to stay current."

---

## Recording Checklist

- [ ] Terminal font size ≥ 16pt, high contrast theme
- [ ] Docker Desktop running before recording starts
- [ ] Auth pre-configured (`~/.copilot-sandbox/.copilot/config.json` exists)
- [ ] `FibonacciDemo` session folder does **not** exist yet (fresh demo)
- [ ] Screen recording set to 1920×1080 (or 1280×720 minimum)
- [ ] Narration mic check before full take
- [ ] Build step captured at real speed, then speed-up applied in post (2×–4×)
- [ ] VS Code window positioned so split-screen with terminal is visible
- [ ] `dotnet test` command ready to paste at the end

---

## Commands Reference (copy-paste ready)

```powershell
# 1. Clone & install
git clone https://github.com/VaclavPachta/CopilotCliSandbox
cd CopilotCliSandbox
.\install.ps1 -Add dotnet8,dotnet10,csharpls

# 2. Reload & launch
. $PROFILE
copilot-sandbox FibonacciDemo -Code

# 3. (Optional) Pre-set PAT
$env:COPILOT_SANDBOX_GITHUB_TOKEN = "<your-pat>"

# 4. Future updates
copilot-sandbox -Update
```

```
# Inside the Copilot session:
/login                    ← auth (first time only, if no PAT)

Create a new .NET solution with a class library project and an xUnit test project.
Then implement the Fibonacci sequence in C# using a TDD approach:
write the failing tests first, then implement the function to make them pass.
```
