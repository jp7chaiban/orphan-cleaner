<#
.SYNOPSIS
  Windows installer. Builds "Orphan Cleaner.exe" (a single self-contained file with both PowerShell
  scripts embedded) and, with -Skill, installs the coding-agent skill. Re-run to update.
.DESCRIPTION
  The exe needs nothing else installed. Each time it starts, it unpacks its scripts to
  %LOCALAPPDATA%\OrphanCleaner (so the command-line engine is also available there) and opens the window.
.PARAMETER ExeDir
  Where to put the exe (default: your Desktop).
.PARAMETER Skill
  Also install the agent skill (default location: ~\.claude\skills\orphan-cleaner).
.PARAMETER SkillOnly
  Install only the skill; don't build the exe.
.PARAMETER SkillDir
  Skills folder to install into (default: ~\.claude\skills). Use your agent's skills folder if it isn't Claude Code.
#>
[CmdletBinding()]
param(
    [string]$ExeDir = [Environment]::GetFolderPath('Desktop'),
    [string]$ExeName = 'Orphan Cleaner.exe',
    [switch]$Skill,
    [switch]$SkillOnly,
    [string]$SkillDir = (Join-Path $HOME '.claude\skills')
)

$ErrorActionPreference = 'Stop'
$repo     = Split-Path -Parent $PSScriptRoot
$skillSrc = Join-Path $repo 'skills\orphan-cleaner'
$engine   = Join-Path $skillSrc 'scripts\Find-OrphanProcesses.ps1'
$gui      = Join-Path $repo 'src\windows\OrphanCleaner-GUI.ps1'

if (-not $SkillOnly) {
    $exe = Join-Path $ExeDir $ExeName
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path $csc)) { throw "C# compiler not found at $csc (.NET Framework 4.x is required)." }

    $ico = Join-Path $repo 'assets\icon.ico'   # made by scripts\build-icon.ps1
    New-Item -ItemType Directory -Force $ExeDir | Out-Null
    & $csc /nologo /target:winexe /optimize "/win32icon:$ico" "/out:$exe" /r:System.Windows.Forms.dll `
        "/resource:$engine,Find-OrphanProcesses.ps1" `
        "/resource:$gui,OrphanCleaner-GUI.ps1" `
        "/resource:$ico,OrphanCleaner.ico" `
        (Join-Path $repo 'src\windows\launcher\OrphanCleaner.cs')
    if ($LASTEXITCODE) { throw "Compiling the exe failed (csc exit code $LASTEXITCODE)." }
    Write-Host "Built $exe (self-contained, scripts embedded)."
}

if ($Skill -or $SkillOnly) {
    $dest = Join-Path $SkillDir 'orphan-cleaner'
    New-Item -ItemType Directory -Force $SkillDir | Out-Null
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item $skillSrc $dest -Recurse
    Write-Host "Installed the agent skill to $dest"
}
