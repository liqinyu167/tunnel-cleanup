param(
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

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath) `
    -Verb RunAs
  exit
}

Start-Transcript -Path $log -Append | Out-Null
Write-Host "=== Tunnel cleanup started: $(Get-Date) ==="

function Write-Step($message) {
  Write-Host ''
  Write-Host ">>> $message"
}

function Get-PrimaryPhysicalAdapter {
  $upAdapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Status -eq 'Up' -and
      $_.InterfaceDescription -notmatch 'Virtual|Loopback|TAP|TUN|Tunnel|VPN|Wintun|WireGuard|Hyper-V|VirtualBox|VMware'
    } |
    Sort-Object InterfaceMetric, InterfaceIndex |
    Select-Object -First 1

  if ($upAdapter) { return $upAdapter }

  return Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
    Where-Object {
      $_.InterfaceDescription -notmatch 'Virtual|Loopback|TAP|TUN|Tunnel|VPN|Wintun|WireGuard|Hyper-V|VirtualBox|VMware'
    } |
    Sort-Object InterfaceIndex |
    Select-Object -First 1
}

function Get-TunnelLikeAdapters {
  Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Name -match 'tun|tap|vpn|wireguard|wintun|meta|clash|mihomo|sing|tailscale|zerotier|openvpn' -or
      $_.InterfaceDescription -match 'tun|tap|vpn|wireguard|wintun|tunnel|meta|clash|mihomo|sing|tailscale|zerotier|openvpn'
    }
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
      Write-Host "Stopping user tunnel/proxy process: $($_.ProcessName) [$($_.Id)]"
      Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
}

function Remove-TunnelDefaultRoutes {
  $tunnelAliases = @(Get-TunnelLikeAdapters | Select-Object -ExpandProperty Name)

  if (-not $tunnelAliases -or $tunnelAliases.Count -eq 0) {
    Write-Host 'No tunnel-like adapters found.'
    return
  }

  Get-NetRoute -ErrorAction SilentlyContinue |
    Where-Object {
      ($_.DestinationPrefix -eq '0.0.0.0/0' -or $_.DestinationPrefix -eq '::/0') -and
      ($tunnelAliases -contains $_.InterfaceAlias)
    } |
    ForEach-Object {
      Write-Host "Removing tunnel default route only: $($_.DestinationPrefix) via $($_.InterfaceAlias)"
      Remove-NetRoute -DestinationPrefix $_.DestinationPrefix -InterfaceIndex $_.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Reset-ProxyState {
  $proxyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  $proxyState = Get-ItemProperty -Path $proxyPath |
    Select-Object ProxyEnable, ProxyServer, ProxyOverride, AutoConfigURL
  $proxyState | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8

  Set-ItemProperty -Path $proxyPath -Name ProxyEnable -Type DWord -Value 0
  Set-ItemProperty -Path $proxyPath -Name AutoConfigURL -Value ''
  netsh winhttp reset proxy
}

function Restart-PhysicalNetwork {
  $adapter = Get-PrimaryPhysicalAdapter
  if (-not $adapter) {
    Write-Warning 'No physical network adapter was found.'
    return
  }

  Write-Host "Selected physical adapter: $($adapter.Name) [$($adapter.InterfaceDescription)]"
  Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
  Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 8

  ipconfig /release $adapter.Name
  ipconfig /renew $adapter.Name

  $adapter = Get-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue
  $ipConfig = Get-NetIPConfiguration -InterfaceAlias $adapter.Name -ErrorAction SilentlyContinue
  $ipv4 = $ipConfig.IPv4Address.IPAddress | Select-Object -First 1
  $gateway = $ipConfig.IPv4DefaultGateway.NextHop | Select-Object -First 1

  Write-Host "Adapter status: $($adapter.Status)"
  Write-Host "IPv4: $ipv4"
  Write-Host "Gateway: $gateway"
  Write-Host "DNS: $($ipConfig.DNSServer.ServerAddresses -join ', ')"

  if (-not $NoOpenPortal -and $adapter.Status -eq 'Up' -and $ipv4 -and $gateway) {
    Write-Step 'Trying to discover a captive portal'
    $headers = & curl.exe --interface $ipv4 -I --max-time 10 'http://www.msftconnecttest.com/connecttest.txt' 2>&1
    $headers | ForEach-Object { Write-Host $_ }

    $locationLine = $headers | Where-Object { $_ -match '^\s*Location:\s*(.+)\s*$' } | Select-Object -First 1
    if ($locationLine -and $locationLine -match '^\s*Location:\s*(.+)\s*$') {
      $portalUrl = $Matches[1].Trim()
      Write-Host "Detected captive portal: $portalUrl"
      Start-Process $portalUrl
    } else {
      Write-Host 'No captive portal redirect was detected.'
    }
  }
}

Write-Step 'Saving and resetting proxy state'
Reset-ProxyState

if (-not $NoStopProcesses) {
  Write-Step 'Stopping user tunnel/proxy processes'
  Stop-UserTunnelProcesses
} else {
  Write-Step 'Skipping process cleanup'
}

Write-Step 'Removing default routes owned by tunnel-like adapters'
Remove-TunnelDefaultRoutes

Write-Step 'Keeping tunnel adapters installed and enabled'
Get-TunnelLikeAdapters |
  Select-Object Name, InterfaceDescription, Status, InterfaceIndex |
  Format-Table -AutoSize

Write-Step 'Refreshing DNS'
ipconfig /flushdns

if (-not $NoRestartAdapter) {
  Write-Step 'Restarting primary physical adapter and renewing DHCP'
  Restart-PhysicalNetwork
} else {
  Write-Step 'Skipping adapter restart'
}

Write-Step 'Final adapter and route state'
Get-NetAdapter | Sort-Object InterfaceIndex |
  Select-Object Name, InterfaceDescription, Status, LinkSpeed, InterfaceIndex |
  Format-Table -AutoSize
route print -4

Write-Host ''
Write-Host "Log: $log"
Write-Host "Proxy state backup: $stateFile"
Write-Host "=== Tunnel cleanup finished: $(Get-Date) ==="
Stop-Transcript | Out-Null
