<#
.SYNOPSIS
  Installs Orphan Process Cleaner: copies the scripts to %LOCALAPPDATA%\OrphanCleaner and
  compiles the "Orphan Cleaner.exe" launcher onto the Desktop. Re-run to update; it overwrites
  the installed copy and the Desktop exe.
.PARAMETER ExeDir
  Where to put the launcher exe (default: your Desktop).
#>
[CmdletBinding()]
param([string]$ExeDir = [Environment]::GetFolderPath('Desktop'))

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA 'OrphanCleaner'
$exe  = Join-Path $ExeDir 'Orphan Cleaner.exe'
$csc  = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw "C# compiler not found at $csc (.NET Framework 4.x is required)." }

New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $repo 'src\Find-OrphanProcesses.ps1'), (Join-Path $repo 'src\OrphanCleaner-GUI.ps1') $dest -Force

# Use Task Manager's icon for the launcher.
Add-Type -AssemblyName System.Drawing
$ico = Join-Path $dest 'OrphanCleaner.ico'
$fs = [IO.File]::Create($ico)
try { [Drawing.Icon]::ExtractAssociatedIcon("$env:WINDIR\System32\Taskmgr.exe").Save($fs) } finally { $fs.Close() }

& $csc /nologo /target:winexe /optimize "/win32icon:$ico" "/out:$exe" /r:System.Windows.Forms.dll (Join-Path $repo 'src\launcher\OrphanCleaner.cs')
if ($LASTEXITCODE) { throw "Compiling the launcher failed (csc exit code $LASTEXITCODE)." }

Write-Host "Installed scripts to $dest"
Write-Host "Launcher: $exe"
