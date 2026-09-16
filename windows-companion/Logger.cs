namespace G9WindowsCompanion;

/// <summary>Simple, bounded file logger. Mirrors the Mac app's diagnostics so
/// remote debugging works: send me companion.log.</summary>
public sealed class Logger
{
    private readonly string _path;
    private readonly object _gate = new();
    private const long MaxBytes = 2 * 1024 * 1024;

    public string LogDirectory { get; }
    public string LogPath => _path;

    public Logger()
    {
        LogDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "G9WindowsCompanion");
        Directory.CreateDirectory(LogDirectory);
        _path = Path.Combine(LogDirectory, "companion.log");
    }

    public void Info(string message) => Write("INFO", message);
    public void Error(string message) => Write("ERROR", message);

    private void Write(string level, string message)
    {
        var line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} {level} {message}";
        lock (_gate)
        {
            try
            {
                if (File.Exists(_path) && new FileInfo(_path).Length > MaxBytes)
                    File.WriteAllText(_path, ""); // simple truncation when it grows too big
                File.AppendAllText(_path, line + Environment.NewLine);
            }
            catch { /* logging must never crash the app */ }
        }
        try { Console.WriteLine(line); } catch { }
    }
}
