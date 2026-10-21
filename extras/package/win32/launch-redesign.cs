using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

// A GUI bootstrapper so development launches can target the user's desktop,
// including when the invoking shell uses a separate automation desktop.
internal static class RedesignLauncher
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StartupInfo
    {
        public int cb;
        public string reserved, desktop, title;
        public int x, y, width, height, xChars, yChars, fill, flags;
        public short showWindow, reservedBytes;
        public IntPtr reservedPointer, stdin, stdout, stderr;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInfo
    {
        public IntPtr process, thread;
        public uint processId, threadId;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateProcessW(string application, StringBuilder commandLine,
        IntPtr processAttributes, IntPtr threadAttributes, bool inheritHandles, uint flags,
        IntPtr environment, string directory, ref StartupInfo startup, out ProcessInfo process);
    [DllImport("kernel32.dll")]
    private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll")]
    private static extern bool GetExitCodeProcess(IntPtr handle, out uint exitCode);
    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr window, string text, string title, uint flags);

    private static string Quote(string value)
    {
        string escaped = Regex.Replace(value, "(\\\\*)\"", "$1$1\\\"");
        return "\"" + Regex.Replace(escaped, "(\\\\+)$", "$1$1") + "\"";
    }

    [STAThread]
    private static int Main(string[] arguments)
    {
        try
        {
            string[] paths = File.ReadAllLines(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,
                "launch-vlc-redesign.paths"));
            if (paths.Length != 5)
                throw new InvalidDataException("Run run-vlc.bat to configure the development launcher.");
            string build = paths[0], source = paths[1], qtBin = paths[2];
            string executable = Path.Combine(build, "bin", "vlc-redesign.exe");
            if (!File.Exists(executable))
                throw new FileNotFoundException("Build VLC Redesign first.", executable);
            string profile = Path.Combine(build, "redesign-profile");
            Directory.CreateDirectory(profile);
            Environment.SetEnvironmentVariable("PATH", Path.Combine(build, "src") + ";" +
                Path.Combine(build, "lib") + ";" + qtBin + ";" + Environment.GetEnvironmentVariable("PATH"));
            Environment.SetEnvironmentVariable("VLC_DEVELOPMENT_DLL_DIRECTORY", qtBin);
            Environment.SetEnvironmentVariable("VLC_PLUGIN_PATH", Path.Combine(build, "modules"));
            Environment.SetEnvironmentVariable("VLC_LIBEXEC_PATH", Path.Combine(build, "bin"));
            Environment.SetEnvironmentVariable("VLC_DATA_PATH", Path.Combine(source, "share"));
            Environment.SetEnvironmentVariable("VLC_LOCALE_PATH", Path.Combine(build, "po"));
            Environment.SetEnvironmentVariable("VLC_CONFIG_PATH", profile);
            Environment.SetEnvironmentVariable("VLC_CACHE_PATH", profile);
            Environment.SetEnvironmentVariable("VLC_USERDATA_PATH", profile);
            Environment.SetEnvironmentVariable("QT_PLUGIN_PATH", paths[3]);
            Environment.SetEnvironmentVariable("QML2_IMPORT_PATH", paths[4]);
            Environment.SetEnvironmentVariable("QT_QPA_PLATFORM", "windows");

            var command = new StringBuilder(Quote(executable));
            foreach (string argument in new[] { "-I", "qt", "--no-one-instance",
                "--no-one-instance-when-started-from-file", "--no-qt-start-minimized" })
                command.Append(" ").Append(Quote(argument));
            foreach (string argument in arguments)
                command.Append(" ").Append(Quote(argument));
            var startup = new StartupInfo {
                cb = Marshal.SizeOf(typeof(StartupInfo)), desktop = @"winsta0\default",
                flags = 1, showWindow = 1
            };
            ProcessInfo process;
            if (!CreateProcessW(executable, command, IntPtr.Zero, IntPtr.Zero, false, 0,
                IntPtr.Zero, Environment.CurrentDirectory, ref startup, out process))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            CloseHandle(process.thread);
            try
            {
                File.WriteAllText(Path.Combine(build, "redesign-last-launch.txt"),
                    "PID=" + process.processId + Environment.NewLine +
                    "Desktop=winsta0\\default" + Environment.NewLine + executable);
                WaitForSingleObject(process.process, UInt32.MaxValue);
                uint exitCode;
                return GetExitCodeProcess(process.process, out exitCode) ? (int)exitCode : 1;
            }
            finally { CloseHandle(process.process); }
        }
        catch (Exception error)
        {
            MessageBoxW(IntPtr.Zero, error.Message, "VLC Redesign launch failed", 0x10);
            return 1;
        }
    }
}
