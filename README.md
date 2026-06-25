# 隧道网络清扫 / Tunnel Cleanup

这是一个轻量的 Windows 网络清理脚本，用来处理 Clash、mihomo、TUN、VPN 这类代理软件没有正常退出后留下的网络状态。

它不是驱动修复工具，不会删除、更新或卸载任何网卡驱动。

## 默认会做什么

双击 `TunnelCleanup.bat` 时，默认会做这些事：

- 备份当前 Windows 用户代理设置到 `logs/last-proxy-state.json`
- 关闭 Windows 用户代理，例如清掉 `127.0.0.1:7897`
- 清空 PAC 地址
- 重置 WinHTTP 代理
- 删除 TUN/VPN/Meta/Clash 这类虚拟隧道网卡上的默认路由
- 禁用 Meta/Clash/mihomo/sing-box/Wintun 这类代理隧道网卡

禁用虚拟网卡只是把设备状态切到“禁用”，不会卸载驱动。Clash 的 TUN 功能重新开启时，通常可以重新启用或重建这个虚拟网卡。

## 默认不会做什么

默认不会：

- 卸载虚拟网卡
- 删除驱动
- 更新驱动
- 重启有线或无线物理网卡
- 执行 DHCP release/renew
- 刷新 DNS 缓存
- 停止 Clash/mihomo 进程
- 打开校园网认证页
- 修改网卡高级属性

## 使用

普通使用：

```bat
TunnelCleanup.bat
```

先预览，不实际修改：

```powershell
.\TunnelCleanup.ps1 -DryRun
```

如果这次不想禁用 Meta/Clash 虚拟网卡：

```powershell
.\TunnelCleanup.ps1 -NoDisableMetaTunnel
```

如果发现 Clash/mihomo 在后台反复写回代理，可以手动使用更强一点的模式：

```powershell
.\TunnelCleanup.ps1 -StopProcesses
```

额外动作需要显式打开：

```powershell
.\TunnelCleanup.ps1 -FlushDns
.\TunnelCleanup.ps1 -RestartAdapter
.\TunnelCleanup.ps1 -OpenPortal
```

## 权限说明

关闭用户代理不需要管理员权限。

删除虚拟隧道默认路由、禁用 Meta/Clash 虚拟网卡需要管理员权限。`TunnelCleanup.bat` 会自动请求管理员权限。

## 文件

- `TunnelCleanup.ps1`: 主脚本
- `TunnelCleanup.bat`: 双击启动器
- `logs/`: 运行日志和代理状态备份
