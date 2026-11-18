---
name: orphan-cleaner
description: Find and kill orphaned processes left behind by coding agents and closed terminals - forgotten `tail -f | grep` watchers, sleep/poll loops, test runners, dev servers - on Windows, macOS and Linux (incl. WSL). Use when the machine is slow or CPU/RAM is high, a port is unexpectedly in use, after finishing work that started background commands, or when the user asks to clean up leftover, stuck, zombie or orphaned processes.
---

# Orphan Cleaner

Coding agents start background commands (log watchers, test runs, dev servers). When a tool call
times out, a session ends or a terminal closes, those commands often keep running with nobody reading
their output. This skill finds them and kills them safely.

The engines are in this skill's `scripts/` folder. Below, `<skill-dir>` means this skill's base directory.

## 1. Report (always do this first; it kills nothing)

**Windows** (PowerShell):

```powershell
& "<skill-dir>\scripts\Find-OrphanProcesses.ps1" -AsObject -IncludeRuntimes |
  Select-Object Id, Name, Tier, AgeHours, CpuSec, TreeMB, Children, Ports, Command | ConvertTo-Json
```

**macOS / Linux / WSL** (bash):

```bash
bash "<skill-dir>/scripts/orphan-cleaner.sh" --json --include-runtimes
```

Both list only processes that (1) lost their parent, (2) are on a dev-tool name list, (3) are older
than 30 minutes (`-MinAgeMinutes N` / `--min-age N` to change), and (4) are not part of a live session
(Claude Code, VS Code, Cursor, terminals, tmux, IDEs are always excluded).

## 2. Decide what to kill

| Tier | What it is | Policy |
|---|---|---|
| `helper` | leftover `grep`, `tail`, `sleep`, `sed`, ... | Safe. Kill when the user asked for cleanup or they are your own leftovers. |
| `pipeline` (macOS/Linux) | an orphaned shell running only helpers, e.g. `bash -c "tail -f log \| grep x"` | Same as helper. |
| `runtime` | `node`, `python`, `bash`, `npx`, ... | **Ask the user first.** Show PID, age and command line. |
| anything with **ports** | still listening, i.e. a server | **Ask the user first.** It may be a dev server they rely on. |

Read the command line before killing. A long-running watcher that a *live* session still uses can look
orphaned, especially on WSL, where commands started from Windows with `wsl.exe` have no Linux parent.

## 3. Kill

**Windows**: kill helpers (no prompt):

```powershell
& "<skill-dir>\scripts\Find-OrphanProcesses.ps1" -Kill -Force
```

To kill one specific runtime the user approved, kill it **and its children** by PID:

```powershell
$o = & "<skill-dir>\scripts\Find-OrphanProcesses.ps1" -AsObject -IncludeRuntimes | Where-Object Id -eq <PID>
$o._Tree | Sort-Object CreationDate -Descending | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
```

**macOS / Linux**: kill helpers and pipelines (no prompt):

```bash
bash "<skill-dir>/scripts/orphan-cleaner.sh" --kill --yes
```

To kill one specific approved runtime, use the `tree` array from the JSON (deepest first):

```bash
kill -TERM <tree PIDs in reverse order>; sleep 1; kill -KILL <any still alive> 2>/dev/null
```

Never use `--include-runtimes --kill --yes` / `-IncludeRuntimes -Kill -Force` without the user's explicit OK.

## 4. Report back

Tell the user what you killed (name, PID, age, what it was doing), what you left running and why, and
for anything you left that needs a decision, ask. If the machine is still slow afterwards, the load is
probably from live sessions (tests and servers still in use), which this tool deliberately does not touch.

## Prevent it

When *you* start a background command, note its PID and stop it as soon as you are done with it.
Before ending a task that started background commands, run the report step and clean up your own leftovers.
