<#
.SYNOPSIS
  Finds (and optionally kills) orphaned dev-tool processes whose parent has exited:
  leftover grep/tail pipes, detached test runners, forgotten dev servers.

.DESCRIPTION
  A process counts as an orphan when its parent PID no longer exists, or the PID has been
  reused by a newer process. Only processes whose name is in the target lists are considered,
  so normal Windows apps that outlive their launcher are never touched.

  Tiers:
    Helpers  (default)          grep, rg, tail, sed, awk, ... - pipe filters; safe to kill.
    Runtimes (-IncludeRuntimes) node, python, bash, npx, ...  - may be servers you still want,
                                                                so they need an explicit opt-in.
  Killing an orphan also kills its whole process tree (e.g. the Nodist shim and the real node).

.PARAMETER Kill
  Actually stop the processes. Without it, the script only reports.
.PARAMETER IncludeRuntimes
  Also target node/python/bash/... orphans.
.PARAMETER MinAgeMinutes
  Ignore orphans younger than this (default 30), so pipelines that are still finishing are left alone.
.PARAMETER Force
  With -Kill, skip the confirmation prompt.

.EXAMPLE
  .\Find-OrphanProcesses.ps1                       # report helper orphans older than 30 min
.EXAMPLE
  .\Find-OrphanProcesses.ps1 -IncludeRuntimes      # also list orphaned node/python servers
.EXAMPLE
  .\Find-OrphanProcesses.ps1 -Kill                 # kill helper orphans (asks first)
.EXAMPLE
  .\Find-OrphanProcesses.ps1 -Kill -Force -MinAgeMinutes 120   # unattended, e.g. scheduled task
#>
[CmdletBinding()]
param(
    [switch]$Kill,
    [switch]$IncludeRuntimes,
    [ValidateRange(0, 100000)][int]$MinAgeMinutes = 30,
    [switch]$Force,
    # Return the orphan objects (with their process trees) instead of printing; used by the GUI.
    [switch]$AsObject
)

$HelperNames  = 'grep','egrep','fgrep','rg','tail','head','sed','awk','gawk','cat','tee','less','more','sort','uniq','wc','xargs','find','sleep','timeout','watch'
$RuntimeNames = 'node','npx','npm','python','python3','pythonw','pytest','bash','sh','dash','zsh','deno','bun','uvicorn','java','ruby','perl'
# A tree containing any of these is a live interactive session (e.g. a Claude Code CLI launched
# from a .cmd whose terminal tab closed) and is never reported or killed. cmd/conhost/powershell
# are deliberately not targets: they are usually the launchers of exactly such sessions.
$ProtectedTreeNames = 'claude','Code','WindowsTerminal','explorer','devenv','idea64','pycharm64','cursor'

$targets = $HelperNames
if ($IncludeRuntimes) { $targets += $RuntimeNames }
$targetSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$targets, [StringComparer]::OrdinalIgnoreCase)

$now   = Get-Date
$all   = @(Get-CimInstance Win32_Process)
$byId  = @{}; foreach ($p in $all) { $byId[[int]$p.ProcessId] = $p }
$childrenOf = @{}
foreach ($p in $all) {
    $k = [int]$p.ParentProcessId
    if (-not $childrenOf.ContainsKey($k)) { $childrenOf[$k] = [System.Collections.Generic.List[object]]::new() }
    $childrenOf[$k].Add($p)
}

# Never touch this script's own ancestry (the shell running it, the terminal, etc.).
$protected = [System.Collections.Generic.HashSet[int]]::new()
$cur = [int]$PID
while ($cur -and $byId.ContainsKey($cur) -and $protected.Add($cur)) { $cur = [int]$byId[$cur].ParentProcessId }

function Test-ParentAlive($proc) {
    $parent = $byId[[int]$proc.ParentProcessId]
    if (-not $parent) { return $false }
    # PID reuse: a "parent" created after the child is a different process.
    if ($parent.CreationDate -and $proc.CreationDate -and $parent.CreationDate -gt $proc.CreationDate) { return $false }
    return $true
}

function Get-Descendants([int]$rootId) {
    $out = @(); $queue = [System.Collections.Generic.Queue[int]]::new(); $queue.Enqueue($rootId)
    while ($queue.Count) {
        $id = $queue.Dequeue()
        foreach ($c in @($childrenOf[$id]) | Where-Object { $_ -and $_.CreationDate -ge $byId[$id].CreationDate }) {
            $out += $c; $queue.Enqueue([int]$c.ProcessId)
        }
    }
    $out
}

$listening = @{}
try {
    Get-NetTCPConnection -State Listen -ErrorAction Stop | ForEach-Object {
        $listening[[int]$_.OwningProcess] = @($listening[[int]$_.OwningProcess]) + $_.LocalPort | Where-Object { $_ } | Sort-Object -Unique
    }
} catch { }

$orphans = foreach ($p in $all) {
    $name = [IO.Path]::GetFileNameWithoutExtension($p.Name)
    if (-not $targetSet.Contains($name)) { continue }
    if ($protected.Contains([int]$p.ProcessId)) { continue }
    if (Test-ParentAlive $p) { continue }
    $ageMin = if ($p.CreationDate) { ($now - $p.CreationDate).TotalMinutes } else { [double]::MaxValue }
    if ($ageMin -lt $MinAgeMinutes) { continue }

    $tree  = @($p) + @(Get-Descendants ([int]$p.ProcessId))
    if ($tree | Where-Object { $ProtectedTreeNames -contains [IO.Path]::GetFileNameWithoutExtension($_.Name) }) { continue }
    $gp   = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
    $ports = ($tree | ForEach-Object { $listening[[int]$_.ProcessId] } | Where-Object { $_ } | Sort-Object -Unique) -join ','
    [pscustomobject]@{
        Id       = [int]$p.ProcessId
        Name     = $name
        Tier     = if ($HelperNames -contains $name) { 'helper' } else { 'runtime' }
        Started  = $p.CreationDate
        AgeHours = [math]::Round($ageMin / 60, 1)
        CpuSec   = if ($gp) { [int]$gp.CPU } else { $null }
        TreeMB   = [int](($tree | Measure-Object WorkingSetSize -Sum).Sum / 1MB)
        Children = $tree.Count - 1
        Ports    = $ports
        Command  = if ($p.CommandLine) { $p.CommandLine.Substring(0, [Math]::Min(120, $p.CommandLine.Length)) } else { '' }
        _Tree    = $tree
    }
}

# A child of another orphan is already covered by that orphan's tree kill.
$orphanIds = @($orphans | ForEach-Object Id)
$orphans = @($orphans | Where-Object { $orphanIds -notcontains [int]$byId[$_.Id].ParentProcessId } | Sort-Object Started)

if ($AsObject) { return $orphans }

if (-not $orphans.Count) {
    Write-Host "No orphaned processes found (older than $MinAgeMinutes min$(if(-not $IncludeRuntimes){', helpers only'}))." -ForegroundColor Green
    return
}

$orphans | Select-Object Id, Name, Tier, Started, AgeHours, CpuSec, TreeMB, Children, Ports, Command |
    Format-Table -AutoSize -Wrap | Out-String -Width 250 | Write-Host
$totalMB = ($orphans | Measure-Object TreeMB -Sum).Sum
Write-Host ("{0} orphan root(s), {1} process(es) total, {2} MB." -f $orphans.Count, ($orphans | ForEach-Object { $_._Tree.Count } | Measure-Object -Sum).Sum, $totalMB)
if ($orphans | Where-Object Ports) { Write-Host "Note: entries with Ports are servers still listening - make sure you don't need them." -ForegroundColor Yellow }

if (-not $Kill) { Write-Host "Report only. Re-run with -Kill to stop them." -ForegroundColor Cyan; return }

if (-not $Force) {
    $answer = Read-Host "Kill these $($orphans.Count) orphan(s) and their children? [y/N]"
    if ($answer -notmatch '^(y|yes)$') { Write-Host 'Cancelled.'; return }
}

foreach ($o in $orphans) {
    # Deepest first so children don't get re-parented mid-kill.
    foreach ($proc in ($o._Tree | Sort-Object CreationDate -Descending)) {
        try {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
            Write-Host ("killed  {0,-6} {1}" -f $proc.ProcessId, $proc.Name)
        } catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
            # already exited
        } catch {
            Write-Warning ("failed  {0,-6} {1}: {2}" -f $proc.ProcessId, $proc.Name, $_.Exception.Message)
        }
    }
}
