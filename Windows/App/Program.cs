using System.Security.Cryptography;
using System.Text;
using System.Windows;
using Kornucopia.Core;

namespace Kornucopia.Windows;

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        var smoke = args.Length == 2 && args[0] == "--smoke-test";
        if (args.Length != 0 && !smoke) return 2;
        var output = smoke ? Path.GetFullPath(args[1]) : null;
        var configured = Environment.GetEnvironmentVariable("KORNUCOPIA_DATA_DIR");
        var directory = smoke ? Path.Combine(output!, "isolated-" + Guid.NewGuid().ToString("N")) : !string.IsNullOrWhiteSpace(configured) ? Path.GetFullPath(configured) : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Kornucopia");
        // A second process never races the same personal board file.
        var mutexName = "Local\\Kornucopia-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(directory.ToUpperInvariant())))[..24];
        using var mutex = new Mutex(true, mutexName, out var first);
        if (!first) { var systemLocale = new Locale("auto"); Ui.Alert(null, "Kornucopia", systemLocale.T("app.alreadyOpen"), systemLocale.T("action.understood")); return 0; }
        var store = new BoardStore(directory);
        var preferences = new PreferenceStore(directory); preferences.Load();
        var locale = new Locale(preferences.Value.Language);
        var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
        var window = new MainWindow(store, preferences, locale, smoke);
        app.SessionEnding += (_, ending) => ending.Cancel = !window.PrepareForClosing();
        if (smoke)
        {
            window.Loaded += async (_, _) =>
            {
                try { await Smoke.Run(window, output!); app.Shutdown(0); }
                catch (Exception error) { Directory.CreateDirectory(output!); File.WriteAllText(Path.Combine(output!, "smoke-failure.txt"), error.GetType().Name + ": " + error.Message); app.Shutdown(1); }
            };
        }
        try { return app.Run(window); }
        finally { store.Flush(); mutex.ReleaseMutex(); }
    }
}
