# Orphan Process Cleaner

**Find and kill the processes your coding agents leave behind, on Windows, macOS and Linux.**

Coding agents (Claude Code, Codex CLI, Cursor, Aider, Copilot agent mode…) run a lot of shell
commands in the background: `tail -f build.log | grep --line-buffered "FAIL|passed"`, test
runners, `npx` dev servers, Playwright servers, `sleep` loops that poll for a port. When the agent's
tool call times out, the session ends, or a terminal tab is closed, the program that started those
commands exits, but the commands themselves often keep running. Nobody reads their output any more,
nobody will ever stop them, and they pile up day after day.

On one real Windows machine after a week of agent work, this tool found:

- a recursive `grep -r` started from a huge folder that had been running for **8 hours** and held **1.1 GB** of RAM,
- **13 `tail -f`** and **13 `grep`** pipe filters from finished test runs, some **5 days old**,
- an orphaned pytest shell script that had burned **570 CPU-seconds**,
- Windows Defender at ~20% CPU, scanning every file those processes kept touching.

The CPU was pinned at 100%. Cleaning up the orphans was the first step to getting it back down.

| | Windows | macOS | Linux / WSL |
|---|---|---|---|
| Command line | `Find-OrphanProcesses.ps1` | `orphan-cleaner` | `orphan-cleaner` |
| Desktop app | `Orphan Cleaner.exe` (window) | – | – |
| Interactive picker | the window | `orphan-cleaner -i` | `orphan-cleaner -i` |
| Agent skill | ✅ | ✅ | ✅ |
| Needs | nothing extra (PowerShell 5.1 + .NET 4, built in) | nothing extra (bash, ps; lsof for ports) | nothing extra (bash, procps; lsof for ports) |

## How it decides what is an orphan

A process is listed only if **all** of these hold:

1. **Its parent is gone.**
   - On Windows: the parent PID no longer exists, or Windows has reused it for a newer process.
   - On macOS and Linux: the process has been re-parented to PID 1 (`launchd`/`init`) or to a subreaper such as `systemd --user`.
2. **Its name is on a known dev-tool list.**
   - *Helpers* (always checked): `grep`, `rg`, `tail`, `head`, `sed`, `awk`, `cat`, `tee`, `sort`, `xargs`, `find`, `sleep`, `timeout`, …
   - *Pipelines* (macOS/Linux, always checked): an orphaned `bash`/`sh`/`zsh` whose whole tree is helpers, such as `bash -c "tail -f log | grep x"`.
   - *Runtimes* (only when you opt in): `node`, `npx`, `npm`, `python`, `pytest`, `bash`, `sh`, `deno`, `bun`, `uvicorn`, `java`, …
3. **It is older than the minimum age** (default 30 minutes), so pipelines that are still finishing are left alone.
4. **Nothing in its process tree is a live interactive program.** Trees containing `claude`, VS Code, Cursor,
   Windsurf, Zed, JetBrains IDEs, terminals (Windows Terminal, iTerm2, GNOME Terminal, kitty, …), `tmux`,
   `screen` or `sshd` are skipped. On Windows, `cmd`, `conhost` and `powershell` are never targets,
   because they are usually the launchers of live agent sessions.
5. On macOS/Linux, it belongs to **you** (same user ID).

Killing an orphan kills its whole process tree, children first. Right before it kills a process, the tool
checks again that the PID still belongs to the same process, so a PID that was reused in the meantime is
never hit. The shell running the tool is never touched.

## Install

```bash
git clone https://github.com/jp7chaiban/orphan-cleaner.git
cd orphan-cleaner
```

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1            # build the Desktop exe
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Skill     # ...and install the agent skill
```

This builds **`Orphan Cleaner.exe`** on your Desktop using the C# compiler built into Windows. The exe is
**self-contained**: both PowerShell scripts are embedded in it, so you can copy it to another folder or
another PC. Each time it starts, it unpacks its scripts to `%LOCALAPPDATA%\OrphanCleaner`, so the
command-line engine is available there too after the first run.

> Windows Defender sometimes flags a freshly compiled, unsigned exe. If it quarantines the exe, re-run the
> installer, or run the window straight from the repo with
> `powershell -ExecutionPolicy Bypass -File .\src\windows\OrphanCleaner-GUI.ps1`.

### macOS and Linux (including WSL)

```bash
scripts/install.sh            # installs the `orphan-cleaner` command into ~/.local/bin
scripts/install.sh --skill    # ...and installs the agent skill
```

Set `BIN_DIR=...` or `SKILL_DIR=...` to install somewhere else. You can also run the engine straight from
the repo: `bash skills/orphan-cleaner/scripts/orphan-cleaner.sh`.

To update on any OS, `git pull` and run the installer again.

## Use it

### Windows: the window

Double-click **Orphan Cleaner** on your Desktop. It scans straight away.

| Row colour | Meaning | Ticked by default? |
|---|---|---|
| white | Leftover helper (`grep`, `tail`, `sleep`…) | ✅ yes |
| blue | Runtime (`node`, `python`, `bash`…) | ❌ no |
| yellow | Still **listening on a port**: probably a dev server | ❌ no, check it first |

Tick **"Also show node / python / bash"** to include runtimes, change **"Older than … minutes"** to be more
or less cautious, then click **Kill selected** and confirm.

### Windows: the command line

```powershell
$oc = "$env:LOCALAPPDATA\OrphanCleaner\Find-OrphanProcesses.ps1"   # or skills\orphan-cleaner\scripts\ in the repo

& $oc                                    # report helper orphans older than 30 min (kills nothing)
& $oc -IncludeRuntimes                   # also report node/python/bash orphans and their ports
& $oc -Kill                              # kill helper orphans (asks once)
& $oc -Kill -Force -MinAgeMinutes 120    # unattended: no prompt, only orphans older than 2 h
& $oc -AsObject                          # return objects instead of printing, for scripting
```

### macOS / Linux: the command line

```bash
orphan-cleaner                   # report helpers and pipelines older than 30 min (kills nothing)
orphan-cleaner -r                # also report node/python/bash/... and their listening ports
orphan-cleaner -i                # numbered list; type the rows to kill (s = all safe rows, a = all)
orphan-cleaner -k                # kill everything listed (asks once); -k -y skips the question
orphan-cleaner -m 120            # only orphans older than 2 hours
orphan-cleaner -j -r             # one JSON object per orphan, for scripts and agents
```

```
  #  PID     NAME      TIER        AGE PROCS  PORTS       COMMAND
  1  14706   sleep     helper     2.1h     1  -           sleep 3000
  2  14708   bash      pipeline   5.3d     3  -           bash -c tail -f /dev/null | grep zzz
  3  3820    npm       runtime    1.6h     5  3000,5801   npm exec tsx src/index.ts --web
```

Without a kill option, nothing is ever stopped.

## Use it with coding agents

### Option A: install the skill (recommended)

The repo contains an [Agent Skill](skills/orphan-cleaner/SKILL.md). Once installed, your agent knows
when to look for orphans (slow machine, port already in use, after finishing work that started background
commands, or when you ask), how to run the right engine for the OS, and the safety rules: it kills helpers
on its own and **asks you before touching anything that is a runtime or listens on a port**.

**Claude Code, as a plugin** (stays up to date):

```
/plugin marketplace add jp7chaiban/orphan-cleaner
/plugin install orphan-cleaner@orphan-cleaner
```

**Claude Code, as a plain skill**: run the installer with `-Skill` (Windows) or `--skill` (macOS/Linux).
It copies `skills/orphan-cleaner` to `~/.claude/skills/orphan-cleaner`.

**Other agents that support Agent Skills** (a folder with a `SKILL.md`): copy `skills/orphan-cleaner` into
that agent's skills folder, or point the installer at it with `-SkillDir` / `SKILL_DIR=...`.

Then just ask: *"my laptop is slow, check for orphaned processes"* or *"clean up the background
processes you left running"*.

### Option B: a few lines in your agent's instructions

If your agent doesn't support skills, add this to `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, …:

```markdown
## Background processes
- Every background command you start (`tail -f`, `grep --line-buffered`, dev servers, watchers)
  must be stopped when you are done with it. Kill it by PID; don't leave it for later.
- Before you finish a task that started background commands, check for leftovers:
  Windows: `powershell -NoProfile -File "$env:LOCALAPPDATA\OrphanCleaner\Find-OrphanProcesses.ps1"`
  macOS/Linux: `orphan-cleaner`
- You may kill leftover helpers yourself (`-Kill -Force` / `-k -y`).
- Never kill runtimes (`-IncludeRuntimes` / `-r`) or anything listening on a port without asking me first.
```

### Option C: clean up automatically on a schedule

These kill helper orphans older than two hours, every hour. Runtimes are never killed this way.

**Windows** (Task Scheduler):

```powershell
$oc = "$env:LOCALAPPDATA\OrphanCleaner\Find-OrphanProcesses.ps1"
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
           -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$oc`" -Kill -Force -MinAgeMinutes 120"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName 'Orphan Cleaner' -Action $action -Trigger $trigger -Description 'Kill orphaned dev helper processes'
# remove: Unregister-ScheduledTask -TaskName 'Orphan Cleaner'
```

**macOS / Linux** (cron, via `crontab -e`):

```
0 * * * * $HOME/.local/bin/orphan-cleaner -k -y -m 120 >/dev/null 2>&1
```

## Limitations

- **A long-running watcher in a live session can be listed.** An agent's `tail -f … | grep` monitor that
  is still in use, but older than the minimum age, can look the same as a forgotten one. Read the command
  line before killing, or raise the minimum age.
- **WSL:** commands that a Windows-side agent starts with `wsl.exe` have no Linux parent, so while they run
  they look orphaned to the Linux engine. The 30-minute minimum age usually covers this, but long test runs
  can show up, so check the command line before killing.
- **macOS** support uses only stock tools (bash 3.2, BSD `ps`, `lsof`). It is written for macOS but so far
  has only been tested on Linux (Ubuntu under WSL 2). Reports from Mac users are welcome.
- It only sees processes your user can kill. On Windows, elevated processes may fail to be killed, and the
  tool reports them.
- The protected-name lists are at the top of each engine. Add your own IDE or agent there if it is missing.

## Repository layout

```
skills/orphan-cleaner/SKILL.md                         the agent skill
skills/orphan-cleaner/scripts/Find-OrphanProcesses.ps1 Windows engine (CLI)
skills/orphan-cleaner/scripts/orphan-cleaner.sh        macOS / Linux engine (CLI)
src/windows/OrphanCleaner-GUI.ps1                      Windows window (WinForms)
src/windows/launcher/OrphanCleaner.cs                  self-contained exe that carries the scripts
scripts/install.ps1                                    Windows installer (exe, -Skill)
scripts/install.sh                                     macOS / Linux installer (command, --skill)
.claude-plugin/                                        Claude Code plugin + marketplace manifests
```
