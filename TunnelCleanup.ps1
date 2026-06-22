param(
  [switch]$DryRun,
  [switch]$StopProcesses,
  [switch]$FlushDns,
  [switch]$RestartAdapter,
  [switch]$OpenPortal,
  [switch]$NoStopProcesses,
  [switch]$NoRestartAdapter,
  [switch]$NoOpenPortal,
  [string]$LogDirectory = ''
)

$ErrorActionPreference = 'Continue'

$scriptRoot = Split-Path -Parent $PSCommandPath
if (-not $LogDirectory) {
  $LogDirectory = Join-Path $scriptRoot 'logs'
}

New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
$log = Join-Path $LogDirectory 'tunnel-cleanup.log'
$stateFile = Join-Path $LogDirectory 'last-proxy-state.json'

Start-Transcript -Path $log -Append | Out-Null
Write-Host "=== Tunnel cleanup started: $(Get-Date) ==="
Write-Host 'Mode: gentle cleanup. No adapter restart, no DHCP renew, no DNS flush, no driver changes.'
if ($DryRun) {
  Write-Host 'Dry run mode: no changes will be made.'
}

function Write-Step($message) {
  Write-Host ''
  Write-Host ">>> $message"
}

function Test-IsAdmin {
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TunnelLikeAdapters {
  Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Name -match 'tun|tap|vpn|wireguard|wintun|meta|clash|mihomo|sing|tailscale|zerotier|openvpn' -or
      $_.InterfaceDescription -match 'tun|tap|vpn|wireguard|wintun|tunnel|meta|clash|mihomo|sing|tailscale|zerotier|openvpn'
    }
}

function Get-TunnelDefaultRoutes {
  $tunnelAliases = @(Get-TunnelLikeAdapters | Select-Object -ExpandProperty Name)
  if (-not $tunnelAliases -or $tunnelAliases.Count -eq 0) {
    return @()
  }

  @(Get-NetRoute -ErrorAction SilentlyContinue |
    Where-Object {
      ($_.DestinationPrefix -eq '0.0.0.0/0' -or $_.DestinationPrefix -eq '::/0') -and
      ($tunnelAliases -contains $_.InterfaceAlias)
    })
}

function Reset-ProxyState {
  $proxyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  $proxyState = Get-ItemProperty -Path $proxyPath |
    Select-Object ProxyEnable, ProxyServer, ProxyOverride, AutoConfigURL
  $proxyState | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8

  if ($DryRun) {
    Write-Host "Would disable user proxy at $proxyPath"
    Write-Host 'Would clear AutoConfigURL and ProxyServer.'
    Write-Host 'Would reset WinHTTP proxy.'
    return
  }

  Set-ItemProperty -Path $proxyPath -Name ProxyEnable -Type DWord -Value 0 -ErrorAction SilentlyContinue
  Set-ItemProperty -Path $proxyPath -Name AutoConfigURL -Value '' -ErrorAction SilentlyContinue
  Remove-ItemProperty -Path $proxyPath -Name ProxyServer -ErrorAction SilentlyContinue
  netsh winhttp reset proxy
}

function Stop-UserTunnelProcesses {
  $processPatterns = @(
    'clash',
    'mihomo',
    'sing-box',
    'v2ray',
    'xray',
    'openvpn',
    'wireguard',
    'tailscale',
    'zerotier'
  )

  Get-Process -ErrorAction SilentlyContinue |
    Where-Object {
      $process = $_
      if ($process.ProcessName -match 'service|daemon') { return $false }
      $processPatterns | Where-Object {
        $process.ProcessName -match $_ -or $process.MainWindowTitle -match $_
      }
    } |
    ForEach-Object {
      if ($DryRun) {
        Write-Host "Would stop user proxy process: $($_.ProcessName) [$($_.Id)]"
      } else {
        Write-Host "Stopping user proxy process: $($_.ProcessName) [$($_.Id)]"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
      }
    }
}

function Remove-TunnelDefaultRoutes {
  $routes = @(Get-TunnelDefaultRoutes)
  if (-not $routes -or $routes.Count -eq 0) {
    Write-Host 'No tunnel default routes found.'
    return
  }

  if (-not (Test-IsAdmin)) {
    Write-Warning 'Tunnel default routes exist, but route cleanup needs administrator permission.'
    Write-Warning 'Right-click TunnelCleanup.bat and choose Run as administrator to remove them.'
  }

  foreach ($route in $routes) {
    if ($DryRun) {
      Write-Host "Would remove tunnel default route only: $($route.DestinationPrefix) via $($route.InterfaceAlias)"
    } elseif (Test-IsAdmin) {
      Write-Host "Removing tunnel default route only: $($route.DestinationPrefix) via $($route.InterfaceAlias)"
      Remove-NetRoute -DestinationPrefix $route.DestinationPrefix -InterfaceIndex $route.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
    }
  }
}

function Restart-PhysicalNetwork {
  $adapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Status -eq 'Up' -and
      $_.InterfaceDescription -notmatch 'Virtual|Loopback|TAP|TUN|Tunnel|VPN|Wintun|WireGuard|Hyper-V|VirtualBox|VMware'
    } |
    Sort-Object InterfaceMetric, InterfaceIndex |
    Select-Object -First 1

  if (-not $adapter) {
    Write-Warning 'No active physical network adapter was found.'
    return
  }

  if ($DryRun) {
    Write-Host "Would restart physical adapter: $($adapter.Name)"
    return
  }

  if (-not (Test-IsAdmin)) {
    Write-Warning 'Adapter restart needs administrator permission. Skipped.'
    return
  }

  Write-Host "Restarting physical adapter: $($adapter.Name) [$($adapter.InterfaceDescription)]"
  Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
  Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
}

function Open-CaptivePortalProbe {
  $url = 'http://www.msftconnecttest.com/redirect'
  if ($DryRun) {
    Write-Host "Would open captive portal probe: $url"
  } else {
    Start-Process $url
  }
}

Write-Step 'Saving and resetting proxy state'
Reset-ProxyState

if ($StopProcesses -and -not $NoStopProcesses) {
  Write-Step 'Stopping user proxy processes'
  Stop-UserTunnelProcesses
} else {
  Write-Step 'Skipping process cleanup'
}

Write-Step 'Removing default routes owned by tunnel-like adapters'
Remove-TunnelDefaultRoutes

Write-Step 'Keeping all adapters installed and enabled'
Get-TunnelLikeAdapters |
  Select-Object Name, InterfaceDescription, Status, InterfaceIndex |
  Format-Table -AutoSize

if ($FlushDns) {
  Write-Step 'Refreshing DNS'
  if ($DryRun) {
    Write-Host 'Would flush DNS.'
  } else {
    ipconfig /flushdns
  }
} else {
  Write-Step 'Skipping DNS flush'
}

if ($RestartAdapter -and -not $NoRestartAdapter) {
  Write-Step 'Restarting primary physical adapter'
  Restart-PhysicalNetwork
} else {
  Write-Step 'Skipping adapter restart'
}

if ($OpenPortal -and -not $NoOpenPortal) {
  Write-Step 'Opening captive portal probe'
  Open-CaptivePortalProbe
} else {
  Write-Step 'Skipping captive portal probe'
}

Write-Step 'Final proxy and route state'
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
  Select-Object ProxyEnable, ProxyServer, AutoConfigURL |
  Format-List
netsh winhttp show proxy
Get-NetRoute -AddressFamily IPv4 |
  Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } |
  Sort-Object RouteMetric, InterfaceMetric |
  Select-Object DestinationPrefix, NextHop, InterfaceAlias, InterfaceIndex, RouteMetric, InterfaceMetric |
  Format-Table -AutoSize

Write-Host ''
Write-Host "Log: $log"
Write-Host "Proxy state backup: $stateFile"
Write-Host "=== Tunnel cleanup finished: $(Get-Date) ==="
Stop-Transcript | Out-Null
