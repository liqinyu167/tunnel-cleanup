# 隧道网络清扫 / Tunnel Cleanup

这是一个很简单的 Windows 网络清理脚本，用来处理代理软件、VPN、TUN/TAP、转发隧道没有正常退出后留下的网络状态。

它的目标不是“修驱动”，也不会动任何网卡驱动。它只清理一些代理软件常见残留：

- Windows 系统代理还指向本机端口，例如 `127.0.0.1:7897`
- WinHTTP 代理残留
- TUN/TAP/VPN/代理虚拟网卡留下的默认路由
- DNS 缓存
- 可选：重启主物理网卡并重新 DHCP

## 不会做什么

这个脚本不会：

- 卸载驱动
- 删除驱动
- 更新驱动
- 禁用虚拟网卡
- 卸载虚拟网卡
- 停止 Windows 服务
- 删除普通业务路由
- 修改网卡高级属性
- 写入永久路由

换句话说，它只是把代理/隧道软件可能留下的“网络通道状态”扫干净，让系统回到更接近启动代理软件之前的网络状态。

## 快速使用

双击：

```bat
TunnelCleanup.bat
```

先试运行，不实际修改系统：

```powershell
.\TunnelCleanup.ps1 -DryRun -NoOpenPortal
```

常用参数：

```powershell
.\TunnelCleanup.ps1 -DryRun
.\TunnelCleanup.ps1 -NoStopProcesses
.\TunnelCleanup.ps1 -NoRestartAdapter
.\TunnelCleanup.ps1 -NoOpenPortal
```

日志和代理状态备份会写到：

```text
logs/
```

管理员权限是必须的，因为删除路由、重启网卡这类操作需要提升权限。`-DryRun` 不需要管理员权限。

---

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
.\TunnelCleanup.ps1 -DryRun
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
