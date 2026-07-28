# 安装说明

## 前置条件

1. 路由器已刷 OpenWrt，能 SSH：`ssh root@192.168.x.1`
2. **WAN 口** 网线接到宿舍/校园网口（不要接到 LAN）
3. 电脑能访问路由器 LAN/WiFi（部署时）
4. 已知校园网账号密码

确认 WAN 接口名：

```bash
ip -br link
uci show network.wan
# 常见: wan / eth0.2 / eth1
```

## 方式一：电脑 deploy.sh

```bash
cp .env.example .env
# 填写 ROUTER、账号密码
./deploy.sh --verify
```

需要本机 `ssh`；若用密码登录可装 `sshpass` 并设 `SSH_PASS`。

## 方式二：路由器上 install.sh

```bash
# 用 scp/sftp 把整个目录拷到 /tmp/openwrt-ruijie-minieap
cd /tmp/openwrt-ruijie-minieap
vi files/etc/ruijie/env.example   # 或安装后改 /etc/ruijie/env
sh install.sh --from-env files/etc/ruijie/env.example --start --verify
```

## 开机自启

`install.sh` 会执行：

```bash
/etc/init.d/ruijie-minieap enable
```

服务脚本：`/etc/init.d/ruijie-minieap`（procd，`START=99`，开机约 12s 后再起，等 WAN）。

检查：

```bash
ls -l /etc/rc.d/S99ruijie-minieap
/etc/init.d/ruijie-minieap enabled && echo enabled
```

## 日常恢复（由轻到重）

```bash
# 软续租（优先）
/usr/bin/ruijie-post-auth.sh

# 进程/会话
/etc/init.d/ruijie-minieap restart
/usr/bin/ruijie-post-auth.sh

# 彻底重来（少用）
ruijie-reauth
```

默认 `RUIJIE_DHCP_TYPE=0`：minieap 保活，DHCP 交给 OpenWrt 软 post-auth。  
**不要** `network reload`。

## 掉线看门狗（随 install 一起装）

`install.sh` 会：

1. 安装 `/usr/bin/ruijie-net-watchdog.sh`（软恢复，不循环 reauth）
2. 写入 cron（幂等；默认每 5 分钟 once、每 10 分钟 harvest）：

```cron
*/5 * * * * /usr/bin/ruijie-net-watchdog.sh once
*/10 * * * * /usr/bin/ruijie-net-watchdog.sh harvest
```

3. `cron` enable + restart  
4. 首次 `once` 种子日志 → `/overlay/ruijie-net.log`

| 命令 | 作用 |
|------|------|
| `once` | 探测在线；离线则 start / 软 post-auth / 至多一次 restart（不循环 reauth） |
| `harvest` | 把 `logread` 中 wan/minieap 相关行 append 到持久日志 |
| `snapshot` | 完整现场（ip/route/status/logread）写入日志 |
| `loop` | 前台循环（一般用 cron 即可） |

```bash
grep ruijie-net-watchdog /etc/crontabs/root
tail -50 /overlay/ruijie-net.log
ruijie-net-watchdog.sh once
```

## 改账号

```bash
vi /etc/ruijie/env
/etc/init.d/ruijie-minieap restart
ruijie-minieap-ctl verify
```

## 卸载

```bash
sh uninstall.sh
# 同时删除账号文件：
REMOVE_ENV=1 sh uninstall.sh
# 同时删除持久日志：
REMOVE_LOG=1 sh uninstall.sh
```
