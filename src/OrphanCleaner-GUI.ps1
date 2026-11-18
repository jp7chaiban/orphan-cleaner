<#
  Orphan Process Cleaner - windowed front end for Find-OrphanProcesses.ps1.
  Scans for leftover dev processes whose parent has exited, lets you tick which to kill,
  and kills each one together with its child processes.
#>
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$engine = Join-Path $PSScriptRoot 'Find-OrphanProcesses.ps1'
$script:items = @()

# ---------- window ----------
$form = New-Object Windows.Forms.Form
$form.Text = 'Orphan Process Cleaner'
$form.Size = New-Object Drawing.Size(1100, 600)
$form.MinimumSize = New-Object Drawing.Size(760, 420)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 9.5)
try { $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon("$env:WINDIR\System32\Taskmgr.exe") } catch { }

# ---------- top bar ----------
$top = New-Object Windows.Forms.FlowLayoutPanel
$top.Dock = 'Top'; $top.AutoSize = $true; $top.Padding = '10,10,10,4'; $top.WrapContents = $true

$intro = New-Object Windows.Forms.Label
$intro.Text = 'Finds leftover processes (grep, tail, test runners, dev servers...) whose parent program has already exited. Live Claude Code sessions, editors and terminals are never listed.'
$intro.AutoSize = $true; $intro.MaximumSize = New-Object Drawing.Size(1050, 0); $intro.Margin = '0,0,0,8'
$top.Controls.Add($intro); $top.SetFlowBreak($intro, $true)

$chk = New-Object Windows.Forms.CheckBox
$chk.Text = 'Also show node / python / bash (may be dev servers you still use)'
$chk.AutoSize = $true; $chk.Margin = '0,5,20,0'
$top.Controls.Add($chk)

$lblAge = New-Object Windows.Forms.Label
$lblAge.Text = 'Older than'; $lblAge.AutoSize = $true; $lblAge.Margin = '0,6,4,0'
$top.Controls.Add($lblAge)

$num = New-Object Windows.Forms.NumericUpDown
$num.Minimum = 0; $num.Maximum = 100000; $num.Value = 30; $num.Width = 70; $num.Margin = '0,3,4,0'
$top.Controls.Add($num)

$lblMin = New-Object Windows.Forms.Label
$lblMin.Text = 'minutes'; $lblMin.AutoSize = $true; $lblMin.Margin = '0,6,20,0'
$top.Controls.Add($lblMin)

$btnScan = New-Object Windows.Forms.Button
$btnScan.Text = 'Scan again'; $btnScan.AutoSize = $true; $btnScan.Padding = '8,2,8,2'
$top.Controls.Add($btnScan)

# ---------- grid ----------
$grid = New-Object Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.AllowUserToAddRows = $false; $grid.AllowUserToDeleteRows = $false; $grid.AllowUserToResizeRows = $false
$grid.RowHeadersVisible = $false; $grid.SelectionMode = 'FullRowSelect'; $grid.MultiSelect = $true
$grid.BackgroundColor = [Drawing.SystemColors]::Window; $grid.BorderStyle = 'None'
$grid.AutoSizeColumnsMode = 'DisplayedCells'

$colKill = New-Object Windows.Forms.DataGridViewCheckBoxColumn
$colKill.HeaderText = 'Kill'; $colKill.Width = 40
[void]$grid.Columns.Add($colKill)
foreach ($h in 'Name','PID','Type','Age','CPU (s)','RAM (MB)','Children','Ports','Command line') {
    $c = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $c.HeaderText = $h; $c.ReadOnly = $true
    [void]$grid.Columns.Add($c)
}
$grid.Columns[9].AutoSizeMode = 'Fill'
# Commit checkbox clicks immediately so "Kill selected" sees them.
$grid.Add_CurrentCellDirtyStateChanged({ if ($grid.IsCurrentCellDirty) { $grid.CommitEdit('CurrentCellChange') } })

# ---------- bottom bar ----------
$bottom = New-Object Windows.Forms.Panel
$bottom.Dock = 'Bottom'; $bottom.Height = 52; $bottom.Padding = '10,8,10,8'

$status = New-Object Windows.Forms.Label
$status.Dock = 'Fill'; $status.TextAlign = 'MiddleLeft'

$buttons = New-Object Windows.Forms.FlowLayoutPanel
$buttons.Dock = 'Right'; $buttons.AutoSize = $true; $buttons.WrapContents = $false

$btnAll  = New-Object Windows.Forms.Button; $btnAll.Text  = 'Select all';  $btnAll.AutoSize  = $true
$btnNone = New-Object Windows.Forms.Button; $btnNone.Text = 'Select none'; $btnNone.AutoSize = $true
$btnKill = New-Object Windows.Forms.Button; $btnKill.Text = 'Kill selected'; $btnKill.AutoSize = $true
$btnKill.BackColor = [Drawing.Color]::FromArgb(196, 43, 28); $btnKill.ForeColor = [Drawing.Color]::White
$btnKill.FlatStyle = 'Flat'; $btnKill.Padding = '10,2,10,2'
$buttons.Controls.AddRange(@($btnAll, $btnNone, $btnKill))

$bottom.Controls.Add($status); $bottom.Controls.Add($buttons)

$form.Controls.Add($grid); $form.Controls.Add($top); $form.Controls.Add($bottom)

# ---------- logic ----------
function Format-Age([double]$hours) {
    if ($hours -ge 24) { '{0:N1} days' -f ($hours / 24) }
    elseif ($hours -ge 1) { '{0:N1} h' -f $hours }
    else { '{0:N0} min' -f ($hours * 60) }
}

function Invoke-Scan {
    $form.Cursor = 'WaitCursor'; $btnScan.Enabled = $false; $btnKill.Enabled = $false
    $status.Text = 'Scanning processes...'; $form.Refresh()
    try {
        $script:items = @(& $engine -AsObject -IncludeRuntimes:$chk.Checked -MinAgeMinutes ([int]$num.Value))
    } catch {
        $script:items = @()
        [void][Windows.Forms.MessageBox]::Show("Scan failed:`n$($_.Exception.Message)", 'Orphan Process Cleaner', 'OK', 'Error')
    }
    $grid.Rows.Clear()
    foreach ($o in $script:items) {
        $isServer = [bool]$o.Ports
        $type = if ($isServer) { 'Server (listening)' } elseif ($o.Tier -eq 'helper') { 'Leftover helper' } else { 'Runtime' }
        # Helpers are pre-ticked; runtimes and anything listening on a port must be ticked by hand.
        $preTick = ($o.Tier -eq 'helper') -and -not $isServer
        $i = $grid.Rows.Add($preTick, $o.Name, $o.Id, $type, (Format-Age $o.AgeHours), $o.CpuSec, $o.TreeMB, $o.Children, $o.Ports, $o.Command)
        $grid.Rows[$i].Tag = $o
        if ($isServer) { $grid.Rows[$i].DefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(255, 244, 204) }
        elseif ($o.Tier -ne 'helper') { $grid.Rows[$i].DefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(235, 243, 255) }
    }
    if ($script:items.Count -eq 0) {
        $status.Text = 'All clean - no orphaned processes found.'
        $status.ForeColor = [Drawing.Color]::FromArgb(16, 124, 16)
    } else {
        $mb = ($script:items | Measure-Object TreeMB -Sum).Sum
        $status.Text = "$($script:items.Count) orphaned process(es) using $mb MB. Leftover helpers are pre-ticked; blue = runtime, yellow = server still listening (check before killing)."
        $status.ForeColor = [Drawing.SystemColors]::ControlText
    }
    $btnScan.Enabled = $true; $btnKill.Enabled = $script:items.Count -gt 0; $form.Cursor = 'Default'
}

function Invoke-Kill {
    $grid.EndEdit()
    $selected = @($grid.Rows | Where-Object { $_.Cells[0].Value -eq $true } | ForEach-Object { $_.Tag })
    if (-not $selected.Count) {
        [void][Windows.Forms.MessageBox]::Show('Tick the processes you want to kill first.', 'Orphan Process Cleaner', 'OK', 'Information')
        return
    }
    $list = ($selected | Select-Object -First 15 | ForEach-Object { "  - $($_.Name) (PID $($_.Id))$(if ($_.Ports) { "  port $($_.Ports)" })" }) -join "`n"
    if ($selected.Count -gt 15) { $list += "`n  ...and $($selected.Count - 15) more" }
    $answer = [Windows.Forms.MessageBox]::Show("Kill these $($selected.Count) process(es) and their child processes?`n`n$list", 'Confirm', 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }

    $killed = 0; $failed = @()
    foreach ($o in $selected) {
        foreach ($proc in ($o._Tree | Sort-Object CreationDate -Descending)) {
            # Guard against PID reuse since the scan: the live process must have the same start time.
            $live = Get-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue
            if (-not $live) { continue }
            try { if ([math]::Abs(($live.StartTime - $proc.CreationDate).TotalSeconds) -gt 2) { continue } } catch { continue }
            try { Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop; $killed++ }
            catch { $failed += "$($proc.Name) (PID $($proc.ProcessId)): $($_.Exception.Message)" }
        }
    }
    $msg = "Killed $killed process(es)."
    if ($failed) { $msg += "`n`nCould not kill:`n" + ($failed -join "`n") }
    [void][Windows.Forms.MessageBox]::Show($msg, 'Orphan Process Cleaner', 'OK', $(if ($failed) { 'Warning' } else { 'Information' }))
    Invoke-Scan
}

$btnScan.Add_Click({ Invoke-Scan })
$chk.Add_CheckedChanged({ Invoke-Scan })
$btnKill.Add_Click({ Invoke-Kill })
$btnAll.Add_Click({ foreach ($r in $grid.Rows) { $r.Cells[0].Value = $true } })
$btnNone.Add_Click({ foreach ($r in $grid.Rows) { $r.Cells[0].Value = $false } })
$form.Add_Shown({ Invoke-Scan })

[void]$form.ShowDialog()
