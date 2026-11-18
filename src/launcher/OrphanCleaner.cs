// Tiny launcher: double-click to open the Orphan Process Cleaner window without a console.
// Built and installed by scripts\install.ps1.
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

static class OrphanCleanerLauncher
{
    [STAThread]
    static void Main()
    {
        string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OrphanCleaner");
        string gui = Path.Combine(dir, "OrphanCleaner-GUI.ps1");
        if (!File.Exists(gui))
        {
            MessageBox.Show("Orphan Cleaner's files are missing:\n" + gui, "Orphan Process Cleaner",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }
        var psi = new ProcessStartInfo("powershell.exe",
            "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + gui + "\"");
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = dir;
        Process.Start(psi);
    }
}
