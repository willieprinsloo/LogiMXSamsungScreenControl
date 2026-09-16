using Windows.Devices.Bluetooth;
using Windows.Devices.Enumeration;

namespace G9WindowsCompanion;

public enum ConnState { Connected, Disconnected, Unknown }

/// <summary>
/// Polls the keyboard's Bluetooth connection status on Windows.
///
/// The paired keyboard is resolved once (by name substring or exact address) through
/// the fast paired-device enumeration, then each poll reads the cached device object's
/// <c>ConnectionStatus</c>, which the OS keeps current. Nothing here opens a GATT
/// connection or starts a discovery scan, so a poll costs milliseconds.
///
/// (An earlier version queried association endpoints with
/// <c>DeviceInformation.FindAllAsync</c>, which triggers a live Bluetooth scan and
/// blocks ~30s per protocol — the departure-to-switch time was a minute instead of the
/// configured debounce.)
///
/// Mirrors the Mac's system_profiler provider: any failure, unpaired, or device-absent
/// condition => Unknown, never Disconnected.
/// </summary>
public sealed class KeyboardWatcher
{
    private readonly Logger _log;
    private readonly string _nameContains;
    private readonly string? _address;   // normalized: hex digits only, upper-case

    private BluetoothLEDevice? _ble;
    private BluetoothDevice? _classic;
    private string _resolvedName = "";

    private DateTime _lastResolveAttempt = DateTime.MinValue;
    private static readonly TimeSpan ResolveRetry = TimeSpan.FromSeconds(5);

    public KeyboardWatcher(Logger log, string nameContains, string? address)
    {
        _log = log;
        _nameContains = nameContains;
        _address = string.IsNullOrWhiteSpace(address) ? null : NormalizeAddress(address);
    }

    public async Task<ConnState> PollAsync()
    {
        try
        {
            if (_ble == null && _classic == null)
            {
                if (DateTime.Now - _lastResolveAttempt < ResolveRetry) return ConnState.Unknown;
                _lastResolveAttempt = DateTime.Now;
                await ResolveAsync();
                if (_ble == null && _classic == null) return ConnState.Unknown;
            }

            if (_ble != null)
            {
                if (_ble.DeviceInformation.Pairing.IsPaired == false) { Forget("BLE device no longer paired"); return ConnState.Unknown; }
                return _ble.ConnectionStatus == BluetoothConnectionStatus.Connected ? ConnState.Connected : ConnState.Disconnected;
            }

            if (_classic!.DeviceInformation.Pairing.IsPaired == false) { Forget("classic device no longer paired"); return ConnState.Unknown; }
            return _classic.ConnectionStatus == BluetoothConnectionStatus.Connected ? ConnState.Connected : ConnState.Disconnected;
        }
        catch (Exception ex)
        {
            _log.Error($"PollAsync error: {ex.Message}");
            Forget(null);
            return ConnState.Unknown;
        }
    }

    /// <summary>Find the paired keyboard among BLE devices first, then classic Bluetooth.</summary>
    private async Task ResolveAsync()
    {
        // BLE (the MX Keys S pairs as BLE).
        var bleDevices = await DeviceInformation.FindAllAsync(BluetoothLEDevice.GetDeviceSelectorFromPairingState(true));
        foreach (var d in bleDevices)
        {
            if (!NameMatches(d)) continue;
            var ble = await BluetoothLEDevice.FromIdAsync(d.Id);
            if (ble == null) continue;
            if (_address != null && !AddressMatches(ble.BluetoothAddress)) { ble.Dispose(); continue; }
            _ble = ble;
            _resolvedName = d.Name;
            _log.Info($"keyboard resolved (BLE): '{d.Name}' addr={FormatAddress(ble.BluetoothAddress)}");
            return;
        }

        // Classic Bluetooth fallback.
        var classicDevices = await DeviceInformation.FindAllAsync(BluetoothDevice.GetDeviceSelectorFromPairingState(true));
        foreach (var d in classicDevices)
        {
            if (!NameMatches(d)) continue;
            var bt = await BluetoothDevice.FromIdAsync(d.Id);
            if (bt == null) continue;
            if (_address != null && !AddressMatches(bt.BluetoothAddress)) { bt.Dispose(); continue; }
            _classic = bt;
            _resolvedName = d.Name;
            _log.Info($"keyboard resolved (classic): '{d.Name}' addr={FormatAddress(bt.BluetoothAddress)}");
            return;
        }

        _log.Error($"no paired Bluetooth device matching name~='{_nameContains}'" +
                   (_address != null ? $" address={_address}" : "") +
                   $" (paired BLE: {string.Join(", ", bleDevices.Select(x => $"'{x.Name}'"))}; " +
                   $"paired classic: {string.Join(", ", classicDevices.Select(x => $"'{x.Name}'"))}); retrying every {ResolveRetry.TotalSeconds:0}s");
    }

    private void Forget(string? reason)
    {
        if (reason != null) _log.Info($"keyboard '{_resolvedName}' dropped: {reason}; will re-resolve");
        _ble?.Dispose(); _ble = null;
        _classic?.Dispose(); _classic = null;
        _resolvedName = "";
    }

    private bool NameMatches(DeviceInformation d)
    {
        // With an explicit address the name filter is skipped; the address decides.
        if (_address != null) return true;
        return !string.IsNullOrEmpty(d.Name) &&
               d.Name.Contains(_nameContains, StringComparison.OrdinalIgnoreCase);
    }

    private bool AddressMatches(ulong address) => FormatAddress(address).Replace(":", "") == _address;

    private static string NormalizeAddress(string a) => a.Replace(":", "").Replace("-", "").ToUpperInvariant();

    private static string FormatAddress(ulong address)
    {
        var hex = address.ToString("X12");
        return string.Join(":", Enumerable.Range(0, 6).Select(i => hex.Substring(i * 2, 2)));
    }
}
