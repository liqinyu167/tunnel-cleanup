# 隧道网络清扫 / Tunnel Cleanup

这是一个很轻量的 Windows 网络清理脚本，用来处理 Clash、mihomo、TUN/TAP、VPN 这类代理软件没有正常退出后留下的网络状态。

它不是驱动修复工具，不会动任何网卡驱动，也不会卸载或禁用虚拟网卡。

## 默认会做什么

双击 `TunnelCleanup.bat` 时，默认只做这些温和操作：

- 备份当前 Windows 用户代理设置到 `logs/last-proxy-state.json`
- 关闭 Windows 用户代理，例如清掉 `127.0.0.1:7897`
- 清空 PAC 地址
- 重置 WinHTTP 代理
- 删除 TUN/TAP/VPN/Meta/Clash 这类虚拟隧道网卡上的默认路由

## 默认不会做什么

新版默认不会：

- 重启有线或无线网卡
- 执行 DHCP release/renew
- 刷新 DNS 缓存
- 停止 Clash/mihomo 进程
- 打开校园网认证页
- 禁用虚拟网卡
- 卸载虚拟网卡
- 删除驱动
- 更新驱动
- 修改网卡高级属性

这样设计是为了尽量只还原“代理软件启动前后留下的系统代理和隧道路由状态”，不碰正常网卡和驱动。

## 使用

普通使用：

```bat
TunnelCleanup.bat
```

先预览，不实际修改：

```powershell
.\TunnelCleanup.ps1 -DryRun
```

如果发现还有 Clash/mihomo 在后台反复写回代理，可以手动使用更强一点的模式：

```powershell
.\TunnelCleanup.ps1 -StopProcesses
```

如果确实需要额外动作，可以显式打开：

```powershell
.\TunnelCleanup.ps1 -FlushDns
.\TunnelCleanup.ps1 -RestartAdapter
.\TunnelCleanup.ps1 -OpenPortal
```

这些额外动作默认都不会执行。

## 权限说明

关闭用户代理不需要管理员权限。

删除虚拟隧道默认路由通常需要管理员权限。如果脚本提示权限不足，请右键 `TunnelCleanup.bat`，选择“以管理员身份运行”。

## 文件

- `TunnelCleanup.ps1`: 主脚本
- `TunnelCleanup.bat`: 双击启动器
- `logs/`: 运行日志和代理状态备份
