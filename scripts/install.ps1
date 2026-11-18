<#
.SYNOPSIS
  Builds "Orphan Cleaner.exe": a single self-contained file with both PowerShell scripts embedded.
  Re-run to update; it overwrites the exe.
.DESCRIPTION
  The exe needs nothing else installed. Each time it starts, it unpacks its scripts to
  %LOCALAPPDATA%\OrphanCleaner (so the command-line engine is also available there) and opens the window.
.PARAMETER ExeDir
  Where to put the exe (default: your Desktop).
#>
[CmdletBinding()]
param([string]$ExeDir = [Environment]::GetFolderPath('Desktop'))

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $repo 'src'
$exe  = Join-Path $ExeDir 'Orphan Cleaner.exe'
$csc  = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw "C# compiler not found at $csc (.NET Framework 4.x is required)." }

# Use Task Manager's icon for the exe.
Add-Type -AssemblyName System.Drawing
$ico = Join-Path ([IO.Path]::GetTempPath()) 'OrphanCleaner-build.ico'
$fs = [IO.File]::Create($ico)
try { [Drawing.Icon]::ExtractAssociatedIcon("$env:WINDIR\System32\Taskmgr.exe").Save($fs) } finally { $fs.Close() }

try {
    & $csc /nologo /target:winexe /optimize "/win32icon:$ico" "/out:$exe" /r:System.Windows.Forms.dll `
        "/resource:$(Join-Path $src 'Find-OrphanProcesses.ps1'),Find-OrphanProcesses.ps1" `
        "/resource:$(Join-Path $src 'OrphanCleaner-GUI.ps1'),OrphanCleaner-GUI.ps1" `
        (Join-Path $src 'launcher\OrphanCleaner.cs')
    if ($LASTEXITCODE) { throw "Compiling the exe failed (csc exit code $LASTEXITCODE)." }
} finally { Remove-Item $ico -ErrorAction SilentlyContinue }

Write-Host "Built $exe (self-contained, scripts embedded)."
