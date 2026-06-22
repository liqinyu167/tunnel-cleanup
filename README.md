# Tunnel Cleanup

Windows cleanup helper for recovering from stale proxy, TUN/TAP, VPN, or local forwarding state.

The script is intentionally conservative: it does not uninstall or disable virtual adapters. It only resets proxy settings, removes default routes owned by tunnel-like adapters, refreshes DNS, and optionally restarts the primary physical network adapter.

## Use Cases

- A proxy/VPN/TUN client was not closed cleanly before shutdown.
- The next boot keeps routing traffic through a stale tunnel.
- Captive portal or intranet login pages do not appear because default traffic is intercepted by a tunnel route.
- Windows system proxy still points to a local port after the proxy client exits.

## Files

- `TunnelCleanup.ps1`: main PowerShell script.
- `TunnelCleanup.bat`: double-click launcher.
- `logs/`: runtime logs and the last proxy-state backup.

## What It Does

- Saves the current Windows proxy state to `logs/last-proxy-state.json`.
- Disables Windows user proxy and resets WinHTTP proxy.
- Stops common user-mode tunnel/proxy processes unless `-NoStopProcesses` is used.
- Removes only default routes (`0.0.0.0/0`, `::/0`) owned by tunnel-like adapters.
- Leaves virtual adapters installed and enabled.
- Flushes DNS.
- Restarts the primary physical adapter and renews DHCP unless `-NoRestartAdapter` is used.
- Tries to detect captive portal redirects unless `-NoOpenPortal` is used.

## Run

Double-click:

```bat
TunnelCleanup.bat
```

Or run directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\TunnelCleanup.ps1
```

Optional flags:

```powershell
.\TunnelCleanup.ps1 -NoStopProcesses
.\TunnelCleanup.ps1 -NoRestartAdapter
.\TunnelCleanup.ps1 -NoOpenPortal
```

## Safety Boundaries

The script does not:

- uninstall drivers,
- disable virtual adapters,
- stop Windows services,
- delete non-default routes,
- change adapter advanced properties,
- persist route changes.

## Notes

Administrator permission is required because route removal and adapter restart need elevation.
