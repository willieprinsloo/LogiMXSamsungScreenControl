using System.Windows.Forms;

namespace G9WindowsCompanion;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        // Single instance.
        using var mutex = new Mutex(true, "G9WindowsCompanion_SingleInstance", out bool isNew);
        if (!isNew) return;

        ApplicationConfiguration.Initialize();
        using var ctx = new CompanionContext();
        Application.Run(ctx);
    }
}

/// <summary>Tray app: watches the keyboard and switches the monitor to the Mac
/// when the keyboard leaves Windows.</summary>
internal sealed class CompanionContext : ApplicationContext
{
    private readonly Logger _log = new();
    private readonly AppConfig _cfg;
    private readonly MonitorController _monitor;
    private readonly KeyboardWatcher _watcher;
    private readonly SwitchPolicy _policy;

    private readonly NotifyIcon _tray;
    private readonly ToolStripMenuItem _statusItem;
    private readonly ToolStripMenuItem _pauseItem;

    private ConnState _lastState = ConnState.Unknown;
    private bool _lastArmed;
    private bool _quit;

    public CompanionContext()
    {
        _cfg = AppConfig.Load(_log.LogDirectory);
        _monitor = new MonitorController(_log);
        _watcher = new KeyboardWatcher(_log, _cfg.KeyboardNameContains, _cfg.KeyboardAddress);
        _policy = new SwitchPolicy(_cfg.DepartureDebounceSeconds, _cfg.ArrivalDebounceSeconds);

        _log.Info($"G9 Windows Companion starting. keyboard~='{_cfg.KeyboardNameContains}' address='{_cfg.KeyboardAddress ?? "(by name)"}' macValue={_cfg.MacInputValue} vcp=0x{_cfg.VcpInputFeature:X2} monitorIndex={_cfg.MonitorIndex}");
        _monitor.LogMonitors();

        _statusItem = new ToolStripMenuItem("Starting…") { Enabled = false };
        _pauseItem = new ToolStripMenuItem("Pause", null, (_, _) => TogglePause());

        var menu = new ContextMenuStrip();
        menu.Items.Add(new ToolStripMenuItem("G9 Keyboard Switch — Windows companion") { Enabled = false });
        menu.Items.Add(_statusItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Switch monitor to Mac now", null, (_, _) => SwitchToMacNow()));
        menu.Items.Add(_pauseItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Open log folder", null, (_, _) => OpenLogFolder()));
        menu.Items.Add(new ToolStripMenuItem("Re-scan monitors (to log)", null, (_, _) => _monitor.LogMonitors()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Quit", null, (_, _) => Quit()));

        _tray = new NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Visible = true,
            Text = "G9 Companion: starting…",
            ContextMenuStrip = menu
        };

        _ = PollLoopAsync();
    }

    private async Task PollLoopAsync()
    {
        int delayMs = (int)(Math.Max(0.2, _cfg.PollIntervalSeconds) * 1000);
        while (!_quit)
        {
            ConnState state = await _watcher.PollAsync();
            bool changed = state != _lastState;
            if (changed)
                _log.Info($"obs: {state} | armed={_policy.Armed}");

            bool doSwitch = _policy.OnObservation(state, DateTime.Now);

            if (_policy.Armed != _lastArmed)
                _log.Info($"armed -> {_policy.Armed}");

            if (doSwitch)
            {
                _log.Info($"stable departure from Windows -> switching monitor to Mac (value {_cfg.MacInputValue})");
                bool ok = await Task.Run(() => _monitor.SetInput(_cfg.VcpInputFeature, _cfg.MacInputValue, _cfg.MonitorIndex));
                _log.Info($"switch-to-Mac result: {(ok ? "at least one write succeeded" : "all writes failed")}");
            }

            _lastState = state;
            _lastArmed = _policy.Armed;
            UpdateStatus();

            try { await Task.Delay(delayMs); } catch { }
        }
    }

    private void SwitchToMacNow()
    {
        _log.Info("manual: switch monitor to Mac now");
        _ = Task.Run(() =>
        {
            bool ok = _monitor.SetInput(_cfg.VcpInputFeature, _cfg.MacInputValue, _cfg.MonitorIndex);
            _log.Info($"manual switch-to-Mac result: {(ok ? "sent" : "failed")}");
        });
    }

    private void TogglePause()
    {
        if (_policy.Paused) { _policy.Resume(); _pauseItem.Text = "Pause"; _log.Info("resumed"); }
        else { _policy.Pause(); _pauseItem.Text = "Resume"; _log.Info("paused"); }
        UpdateStatus();
    }

    private void UpdateStatus()
    {
        string status = _policy.Paused ? "Paused"
            : _lastState switch
            {
                ConnState.Connected => _policy.Armed ? "Armed (keyboard on Windows)" : "Waiting for stable connection",
                ConnState.Disconnected => "Keyboard away",
                _ => "Detection unavailable"
            };
        _statusItem.Text = status;
        string tip = $"G9 Companion: {status}";
        _tray.Text = tip.Length > 63 ? tip[..63] : tip;
    }

    private void OpenLogFolder()
    {
        try { System.Diagnostics.Process.Start("explorer.exe", _log.LogDirectory); } catch { }
    }

    private void Quit()
    {
        _quit = true;
        _tray.Visible = false;
        _log.Info("quit");
        ExitThread();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _tray.Dispose();
        base.Dispose(disposing);
    }
}
