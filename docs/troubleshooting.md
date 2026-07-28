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

## 认证成功但无外网（重启后常见）

**典型现象：**

- `minieap` 日志有「认证成功」，进程也在跑（或认证后马上退出）  
- WAN 仍是认证前隔离地址（如 `172.23.x.x`），外网 ping 不通  
- 手动 `ubus call network.interface.wan renew` 或 `ifup wan` 后 IP 变成可上网段（如 `172.20.x.x`）并恢复  

**原因：** 开机时 OpenWrt 先 DHCP 到隔离 IP；802.1x 成功后 **netifd 不会自动换租**，一直占着旧地址。  
**`restart` 只重启 minieap，不等于完成 DHCP 换段。**

**本仓库处理：**

- `ruijie-post-auth.sh`：认证后强制 WAN 软续租（优先 `ubus renew` + udhcpc USR1）  
- minieap `-c` / `dhcp-script` 调用该脚本  
- **`ruijie-reauth` / `ruijie-minieap-ctl reauth`**：认证 + 多次 post-auth + 在线检测（推荐）  
- 看门狗离线时走 `reauth`  

手动修复（优先）：

```bash
ruijie-reauth
# 或分步：
/usr/bin/ruijie-post-auth.sh
# 或
ubus call network.interface.wan renew
```

同时确认防火墙 WAN masq：

```bash
uci show firewall | grep masq
```

## 为什么 restart 不够、要用 reauth

| 命令 | 做什么 |
|------|--------|
| `restart` | 停/启 minieap → 可能 802.1x 成功，**不一定**换到正式 IP |
| `post-auth` | **只** WAN DHCP 续租（需已经认证过） |
| **`reauth`** | 停干净 → 认证 → post-auth 续租 → 检测在线 |

判断是否卡在隔离网段：

```bash
ip -4 addr show wan
# 仍是 172.23.x → 需要 post-auth / reauth
# 已是 172.20.x 仍不通 → 查路由/DNS/防火墙
```

## 认证成功后 IP 变了

正常。认证前多为隔离网段，认证后应续租到可上网网段；若不变，按上一节强制 renew。

## 日志位置

```bash
logread -e minieap
logread -e ruijie
logread -e ruijie-net-watch
cat /var/log/minieap.log
ruijie-minieap-ctl status
# 持久日志（重启后仍在，看门狗写入）
tail -100 /overlay/ruijie-net.log
```

OpenWrt 默认 `logread` 在内存，**整机重启会丢**。看门狗把关键行和掉线现场写到 `/overlay/ruijie-net.log`，便于事后分析。

## 运行中突然断网

1. **先不要重启**，看是否被自动恢复：

```bash
tail -80 /overlay/ruijie-net.log
# 期望看到 detected offline → recover success
```

2. 手动一次：

```bash
ruijie-reauth
# 或
ruijie-net-watchdog.sh once
```

3. 仍失败再抓 snapshot：

```bash
ruijie-net-watchdog.sh snapshot
ip -4 addr show wan
ip route
```

常见原因：802.1x 会话掉线、卡在隔离 IP 未 renew、WAN 链路闪断。看门狗覆盖前两类。

## 与网页 Portal 的关系

部分环境会同时劫持 HTTP 到 ePortal。本仓库走 **802.1x**。若纯 Portal 学校且无 802.1x，需另写网页脚本，本服务不适用。
