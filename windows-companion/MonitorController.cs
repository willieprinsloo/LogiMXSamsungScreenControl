using System.Runtime.InteropServices;

namespace G9WindowsCompanion;

/// <summary>
/// DDC/CI monitor control via the Windows low-level monitor configuration API
/// (dxva2.dll). Sends VCP feature writes — specifically input-source select
/// (0x60) — to switch the monitor. Works because the companion runs on the
/// currently-displayed input, which the monitor honours.
/// </summary>
public sealed class MonitorController
{
    private readonly Logger _log;
    public MonitorController(Logger log) => _log = log;

    #region P/Invoke

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct PHYSICAL_MONITOR
    {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }

    private delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdc, IntPtr lprc, IntPtr data);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, out uint pdwNumberOfPhysicalMonitors);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint dwPhysicalMonitorArraySize, [Out] PHYSICAL_MONITOR[] pPhysicalMonitorArray);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool SetVCPFeature(IntPtr hMonitor, byte bVCPCode, uint dwNewValue);

    [DllImport("dxva2.dll", SetLastError = true)]
    private static extern bool DestroyPhysicalMonitors(uint dwPhysicalMonitorArraySize, [In] PHYSICAL_MONITOR[] pPhysicalMonitorArray);

    #endregion

    /// <summary>Enumerate every physical monitor handle, in a stable order.</summary>
    private List<PHYSICAL_MONITOR> EnumeratePhysicalMonitors()
    {
        var result = new List<PHYSICAL_MONITOR>();
        var hmonitors = new List<IntPtr>();

        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (h, hdc, rc, data) =>
        {
            hmonitors.Add(h);
            return true;
        }, IntPtr.Zero);

        foreach (var h in hmonitors)
        {
            if (!GetNumberOfPhysicalMonitorsFromHMONITOR(h, out uint count) || count == 0) continue;
            var arr = new PHYSICAL_MONITOR[count];
            if (GetPhysicalMonitorsFromHMONITOR(h, count, arr))
                result.AddRange(arr);
        }
        return result;
    }

    /// <summary>Log all detected monitors (index + description) so the user can set MonitorIndex.</summary>
    public void LogMonitors()
    {
        var monitors = EnumeratePhysicalMonitors();
        _log.Info($"physical monitors found: {monitors.Count}");
        for (int i = 0; i < monitors.Count; i++)
            _log.Info($"  [{i}] {monitors[i].szPhysicalMonitorDescription}");
        if (monitors.Count > 0)
            DestroyPhysicalMonitors((uint)monitors.Count, monitors.ToArray());
    }

    /// <summary>
    /// Write <paramref name="value"/> to VCP <paramref name="vcp"/> on the configured
    /// monitor(s). Returns true if at least one write succeeded.
    /// </summary>
    public bool SetInput(byte vcp, byte value, int monitorIndex)
    {
        var monitors = EnumeratePhysicalMonitors();
        if (monitors.Count == 0)
        {
            _log.Error("SetInput: no physical monitors found");
            return false;
        }

        bool anySuccess = false;
        try
        {
            for (int i = 0; i < monitors.Count; i++)
            {
                if (monitorIndex >= 0 && i != monitorIndex) continue;
                bool ok = SetVCPFeature(monitors[i].hPhysicalMonitor, vcp, value);
                _log.Info($"SetVCPFeature(monitor[{i}] '{monitors[i].szPhysicalMonitorDescription}', vcp=0x{vcp:X2}, value={value}) -> {(ok ? "ok" : $"FAILED (err {Marshal.GetLastWin32Error()})")}");
                anySuccess |= ok;
            }
        }
        finally
        {
            DestroyPhysicalMonitors((uint)monitors.Count, monitors.ToArray());
        }
        return anySuccess;
    }
}
