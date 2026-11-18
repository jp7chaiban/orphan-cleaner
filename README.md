# Orphan Process Cleaner

**Find and kill the processes your coding agents leave behind on Windows.**

Coding agents (Claude Code, Codex CLI, Cursor, Aider, Copilot agent mode…) run a lot of shell
commands in the background: `tail -f build.log | grep --line-buffered "FAIL|passed"`, test
runners, `npx` dev servers, Playwright servers, `sleep` loops that poll for a port. When the agent's
tool call times out, the session ends, or a terminal tab is closed, the program that started those
commands exits — but on Windows its children keep running. Nobody is reading their output any more,
nobody will ever stop them, and they pile up day after day.

On one real machine after a week of agent work, this tool found:

- a recursive `grep -r` started from a huge folder that had been running for **8 hours** and held **1.1 GB** of RAM,
- **13 `tail -f`** and **13 `grep`** pipe filters from finished test runs, some **5 days old**,
- an orphaned pytest shell script that had burned **570 CPU-seconds**,
- Windows Defender at ~20% CPU, scanning every file those processes kept touching.

The CPU was pinned at 100%. Cleaning up the orphans was the first step to getting it back down.

## How it decides what is an orphan

A process is listed only if **all** of these hold:

1. **Its parent has exited.** The parent PID no longer exists, or Windows has reused it for a newer process.
2. **Its name is on a known dev-tool list.**
   - *Helpers* (always checked): `grep`, `rg`, `tail`, `head`, `sed`, `awk`, `cat`, `tee`, `sort`, `xargs`, `find`, `sleep`, `timeout`, …
   - *Runtimes* (only when you opt in): `node`, `npx`, `npm`, `python`, `pytest`, `bash`, `sh`, `deno`, `bun`, `uvicorn`, `java`, …
3. **It is older than the minimum age** (default 30 minutes). On Windows, Git Bash pipelines that are
   still running also look parentless, so very young processes are left alone.
4. **Nothing in its process tree is a live interactive program.** Any tree containing `claude`, VS Code,
   Windows Terminal, Explorer, Cursor or a JetBrains IDE is skipped. `cmd`, `conhost` and `powershell`
   are never targets, because they are usually the launchers of live agent sessions.

Killing an orphan also kills its whole process tree (for example a Node version-manager shim *and*
the real `node.exe` it started). The shell that runs the tool is never touched.

## Install

Requirements: Windows 10/11 with Windows PowerShell 5.1 and .NET Framework 4.x (both ship with
Windows). There is nothing to download.

```powershell
git clone https://github.com/<you>/orphan-cleaner.git
cd orphan-cleaner
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

The installer:

- copies the scripts to `%LOCALAPPDATA%\OrphanCleaner`, and
- compiles a small launcher, **`Orphan Cleaner.exe`**, onto your Desktop using the C# compiler built into Windows.

To install a newer version, run the installer again.

> Windows Defender sometimes flags a freshly compiled, unsigned exe. If it quarantines the launcher,
> re-run the installer, or start the window directly with
> `powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\OrphanCleaner\OrphanCleaner-GUI.ps1"`.

## Use it: the window

Double-click **Orphan Cleaner** on your Desktop. It scans straight away.

| Row colour | Meaning | Ticked by default? |
|---|---|---|
| white | Leftover helper (`grep`, `tail`, `sleep`…) | ✅ yes |
| blue | Runtime (`node`, `python`, `bash`…) | ❌ no |
| yellow | Still **listening on a port**: probably a dev server | ❌ no, check it first |

- Tick **"Also show node / python / bash"** to include runtimes.
- Change **"Older than … minutes"** to be more or less cautious.
- Click **Kill selected** and confirm. Before killing each process, the tool checks again that the PID still
  belongs to the same process (same start time), so a PID that Windows reused in the meantime is never hit.

## Use it: the command line

```powershell
$oc = "$env:LOCALAPPDATA\OrphanCleaner\Find-OrphanProcesses.ps1"

& $oc                                    # report helper orphans older than 30 min (kills nothing)
& $oc -IncludeRuntimes                   # also report node/python/bash orphans and their ports
& $oc -Kill                              # kill helper orphans (asks once)
& $oc -Kill -Force -MinAgeMinutes 120    # unattended: no prompt, only orphans older than 2 h
& $oc -AsObject                          # return objects instead of printing, for scripting
```

Without `-Kill` the script only reports and never stops anything.

## Use it with coding agents

### 1. Tell your agent about it

Add this to your agent's instructions file (`CLAUDE.md`, `AGENTS.md`, `.cursorrules`, …):

```markdown
## Background processes (Windows)
- Every background command you start (`tail -f`, `grep --line-buffered`, dev servers, watchers)
  must be stopped when you are done with it. Kill it by PID; don't leave it for later.
- Before you finish a task that started background commands, check for leftovers:
  `powershell -NoProfile -File "$env:LOCALAPPDATA\OrphanCleaner\Find-OrphanProcesses.ps1"`
- You may kill leftover helpers you started yourself with `-Kill -Force`.
- Never use `-IncludeRuntimes -Kill` without asking me first: runtimes may be dev servers I still use.
```

### 2. Clean up automatically on a schedule

This registers a task that kills helper orphans older than two hours, every hour. Runtimes are never
killed this way.

```powershell
$oc = "$env:LOCALAPPDATA\OrphanCleaner\Find-OrphanProcesses.ps1"
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
           -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$oc`" -Kill -Force -MinAgeMinutes 120"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName 'Orphan Cleaner' -Action $action -Trigger $trigger -Description 'Kill orphaned dev helper processes'
```

To remove it: `Unregister-ScheduledTask -TaskName 'Orphan Cleaner'`.

### 3. When your machine feels slow

Open the window, keep the default ticks, and click **Kill selected**. Then tick **"Also show node / python / bash"** and
look through the blue and yellow rows by hand. If a whole agent session is stuck, it is not listed
here; close that session from its own terminal or app instead.

## Limitations

- **Windows only.** On macOS and Linux, orphans are re-parented to `init`/`launchd`, so you need a different approach.
- **A long-running watcher in a live session may be listed.** An agent's `tail -f … | grep` monitor that
  is still in use, but older than the minimum age, looks the same as a forgotten one. Read the command
  line before killing, or raise `-MinAgeMinutes`.
- It only sees processes your user can see. Elevated or other users' processes may fail to be killed,
  and the tool reports them.
- The protected-name list (`claude`, `Code`, `WindowsTerminal`, …) is in `src/Find-OrphanProcesses.ps1`.
  Add your own IDE or agent there if it is missing.

## Repository layout

```
src/Find-OrphanProcesses.ps1     engine: detection, reporting, killing (CLI)
src/OrphanCleaner-GUI.ps1        the window (WinForms)
src/launcher/OrphanCleaner.cs    tiny exe that opens the window without a console
scripts/install.ps1              installs to %LOCALAPPDATA% and builds the Desktop exe
```
