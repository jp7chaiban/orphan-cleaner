// Self-contained launcher for Orphan Process Cleaner.
// The PowerShell scripts are embedded as resources (see scripts\install.ps1). On each start the exe
// unpacks them to %LOCALAPPDATA%\OrphanCleaner (only rewriting files whose content changed), then
// opens the window with no console. Nothing else needs to be installed.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

static class OrphanCleanerLauncher
{
    const string Title = "Orphan Process Cleaner";
    static readonly string[] Scripts = { "Find-OrphanProcesses.ps1", "OrphanCleaner-GUI.ps1" };

    [STAThread]
    static void Main()
    {
        string dir;
        try
        {
            dir = Unpack(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OrphanCleaner"));
        }
        catch (Exception first)
        {
            try { dir = Unpack(Path.Combine(Path.GetTempPath(), "OrphanCleaner")); }
            catch (Exception second)
            {
                MessageBox.Show("Could not unpack Orphan Cleaner's scripts:\n" + first.Message + "\n" + second.Message,
                    Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
        }

        var psi = new ProcessStartInfo("powershell.exe",
            "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + Path.Combine(dir, "OrphanCleaner-GUI.ps1") + "\"");
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = dir;
        try { Process.Start(psi); }
        catch (Exception e)
        {
            MessageBox.Show("Could not start PowerShell:\n" + e.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    static string Unpack(string dir)
    {
        Directory.CreateDirectory(dir);
        Assembly asm = Assembly.GetExecutingAssembly();
        foreach (string name in Scripts)
        {
            byte[] data;
            using (Stream s = asm.GetManifestResourceStream(name))
            {
                if (s == null) throw new InvalidOperationException("Embedded script missing from exe: " + name);
                data = new byte[s.Length];
                int read = 0;
                while (read < data.Length) read += s.Read(data, read, data.Length - read);
            }
            string target = Path.Combine(dir, name);
            if (!File.Exists(target) || !SameBytes(File.ReadAllBytes(target), data))
                File.WriteAllBytes(target, data);
        }
        return dir;
    }

    static bool SameBytes(byte[] a, byte[] b)
    {
        if (a.Length != b.Length) return false;
        for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
        return true;
    }
}
