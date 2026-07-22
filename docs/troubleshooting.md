# 故障排除

## 一直「正在查找认证服务器」

1. 确认网卡是 **WAN**（`RUIJIE_NIC=wan`），不要用 `eth0` 整口（DSA 下 EAPOL 常需 `wan` 子接口）。  
2. 设置 **`RUIJIE_EAP_BCAST=1`**（锐捷私有组播）。`0` 在很多学校无效。  
3. 网线是否插在路由器 WAN，而不是 LAN。

## minieap 报 `__time64` / `symbol not found`

ipk 与固件 musl 不匹配。换与系统年代接近的包，例如 ImmortalWrt **21.02.x** 的 minieap，不要用过新的 23.05 包打老固件。

```bash
# 看架构
grep ARCH /etc/openwrt_release
# 设置 MINIEAP_IPK_URL 后重装
```

## 认证成功但无外网

```bash
ip route
ping 223.5.5.5
# 防火墙 WAN masq
uci show firewall | grep masq
```

确保 LAN→WAN 转发与 masq 开启。

## 认证成功后 IP 变了

正常。认证前可能是隔离网段，认证后 DHCP 会换到可上网网段。

## 日志位置

```bash
logread -e minieap
logread -e ruijie
cat /var/log/minieap.log
ruijie-minieap-ctl status
```

## 与网页 Portal 的关系

部分环境会同时劫持 HTTP 到 ePortal。本仓库走 **802.1x**。若纯 Portal 学校且无 802.1x，需另写网页脚本，本服务不适用。
