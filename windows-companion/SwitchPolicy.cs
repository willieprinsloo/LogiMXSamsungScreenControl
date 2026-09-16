namespace G9WindowsCompanion;

/// <summary>
/// Windows-first arming gate, departure-based. Symmetric to the Mac policy:
/// arms only after a stable keyboard connection to Windows, then fires exactly
/// once when the keyboard makes a stable departure (goes to the Mac). Firing
/// disarms; a fresh stable connection re-arms. Unknown/unhealthy disarms.
///
/// It does NOT handle the return direction — the Mac switches the monitor to
/// Windows when the keyboard leaves the Mac. Each machine only ever switches
/// the monitor away from itself.
/// </summary>
public sealed class SwitchPolicy
{
    private readonly double _departureDebounce;
    private readonly double _arrivalDebounce;

    private bool _armed;
    private ConnState? _accumState;
    private DateTime _accumSince;
    private bool _paused;

    public bool Armed => _armed;
    public bool Paused => _paused;

    public SwitchPolicy(double departureDebounceSeconds, double arrivalDebounceSeconds)
    {
        _departureDebounce = departureDebounceSeconds;
        _arrivalDebounce = arrivalDebounceSeconds;
    }

    public void Pause()
    {
        _paused = true;
        _armed = false;
        _accumState = null;
    }

    public void Resume()
    {
        _paused = false;
        _armed = false;
        _accumState = null;
    }

    /// <summary>Feed an observation. Returns true when the monitor should be
    /// switched to the Mac now.</summary>
    public bool OnObservation(ConnState state, DateTime now)
    {
        if (_paused) return false;

        if (state == ConnState.Unknown)
        {
            _armed = false;
            _accumState = null;
            return false;
        }

        if (_accumState != state)
        {
            _accumState = state;
            _accumSince = now;
        }
        double elapsed = (now - _accumSince).TotalSeconds;

        switch (state)
        {
            case ConnState.Connected:
                if (elapsed >= _arrivalDebounce && !_armed)
                    _armed = true;                 // arm without switching
                return false;

            case ConnState.Disconnected:
                if (elapsed >= _departureDebounce && _armed)
                {
                    _armed = false;                // one-shot; re-arm on reconnect
                    return true;                   // switch monitor to Mac
                }
                return false;

            default:
                return false;
        }
    }
}
