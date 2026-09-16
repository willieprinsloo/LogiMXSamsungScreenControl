using System.Text.Json;

namespace G9WindowsCompanion;

/// <summary>
/// Companion settings. Sensible defaults for the verified G95NC + MX Keys S setup;
/// override via a settings.json next to the executable or in %LOCALAPPDATA%\G9WindowsCompanion.
/// </summary>
public sealed class AppConfig
{
    /// <summary>Substring match for the keyboard's Bluetooth name (case-insensitive).</summary>
    public string KeyboardNameContains { get; set; } = "MX KEYS";

    /// <summary>Optional exact Bluetooth address to disambiguate identical models (e.g. "AA:BB:CC:DD:EE:FF"). Null = match by name.</summary>
    public string? KeyboardAddress { get; set; } = null;

    /// <summary>DDC VCP feature for input selection. 0x60 on this monitor.</summary>
    public byte VcpInputFeature { get; set; } = 0x60;

    /// <summary>DDC value that selects the Mac's input (HDMI 3) on the G95NC.</summary>
    public byte MacInputValue { get; set; } = 7;

    /// <summary>
    /// Which physical monitor to control. -1 = every monitor that accepts the write
    /// (fine for a single external display); otherwise the 0-based index from the log.
    /// </summary>
    public int MonitorIndex { get; set; } = -1;

    public double PollIntervalSeconds { get; set; } = 1.0;
    public double DepartureDebounceSeconds { get; set; } = 3.0;
    public double ArrivalDebounceSeconds { get; set; } = 1.0;

    private const string FileName = "settings.json";

    public static AppConfig Load(string logDir)
    {
        // Prefer a settings.json next to the exe; fall back to the log/app-data dir.
        foreach (var dir in new[] { AppContext.BaseDirectory, logDir })
        {
            try
            {
                var path = Path.Combine(dir, FileName);
                if (File.Exists(path))
                {
                    var cfg = JsonSerializer.Deserialize<AppConfig>(File.ReadAllText(path));
                    if (cfg != null) return cfg;
                }
            }
            catch { /* fall through to defaults */ }
        }
        return new AppConfig();
    }
}
