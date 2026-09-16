using Windows.Devices.Enumeration;

namespace G9WindowsCompanion;

public enum ConnState { Connected, Disconnected, Unknown }

/// <summary>
/// Polls the keyboard's Bluetooth connection status on Windows via the
/// association-endpoint "IsConnected" property (works for BLE and classic BT,
/// without opening a connection). Mirrors the Mac's system_profiler provider:
/// any failure or device-absent => Unknown, never Disconnected.
/// </summary>
public sealed class KeyboardWatcher
{
    private readonly Logger _log;
    private readonly string _nameContains;
    private readonly string? _address;

    // BLE and classic Bluetooth AEP protocol GUIDs.
    private const string BleProtocol = "{bb7bb05e-5972-42b5-94fc-76eaa7084d49}";
    private const string ClassicProtocol = "{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}";
    private static readonly string[] Props =
    {
        "System.Devices.Aep.IsConnected",
        "System.Devices.Aep.DeviceAddress"
    };

    public KeyboardWatcher(Logger log, string nameContains, string? address)
    {
        _log = log;
        _nameContains = nameContains;
        _address = string.IsNullOrWhiteSpace(address) ? null : address;
    }

    public async Task<ConnState> PollAsync()
    {
        try
        {
            bool anyMatch = false, anyConnected = false, anyDisconnected = false;

            foreach (var protocol in new[] { BleProtocol, ClassicProtocol })
            {
                var selector = $"System.Devices.Aep.ProtocolId:=\"{protocol}\"";
                DeviceInformationCollection devices;
                try
                {
                    devices = await DeviceInformation.FindAllAsync(selector, Props, DeviceInformationKind.AssociationEndpoint);
                }
                catch (Exception ex)
                {
                    _log.Error($"FindAllAsync failed for protocol {protocol}: {ex.Message}");
                    return ConnState.Unknown;
                }

                foreach (var d in devices)
                {
                    if (!Matches(d)) continue;
                    anyMatch = true;
                    if (d.Properties.TryGetValue("System.Devices.Aep.IsConnected", out var val) && val is bool b)
                    {
                        if (b) anyConnected = true; else anyDisconnected = true;
                    }
                }
            }

            if (!anyMatch) return ConnState.Unknown;      // device not currently enumerated
            if (anyConnected && !anyDisconnected) return ConnState.Connected;
            if (anyDisconnected && !anyConnected) return ConnState.Disconnected;
            return ConnState.Unknown;                     // contradictory / property missing
        }
        catch (Exception ex)
        {
            _log.Error($"PollAsync error: {ex.Message}");
            return ConnState.Unknown;
        }
    }

    private bool Matches(DeviceInformation d)
    {
        if (_address != null)
        {
            if (d.Properties.TryGetValue("System.Devices.Aep.DeviceAddress", out var a) && a is string addr)
                return string.Equals(addr.Replace(":", "").Replace("-", ""),
                                     _address.Replace(":", "").Replace("-", ""),
                                     StringComparison.OrdinalIgnoreCase);
            return false;
        }
        return !string.IsNullOrEmpty(d.Name) &&
               d.Name.Contains(_nameContains, StringComparison.OrdinalIgnoreCase);
    }
}
