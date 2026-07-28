# openwrt-ruijie-minieap

OpenWrt 上用 [minieap](https://github.com/updateing/minieap) 完成 **锐捷 802.1x（RJv3）** 校园网认证，多设备经路由器 NAT 共享上网。

在暨南大学宿舍有线口验证通过的关键参数：

| 参数 | 值 | 含义 |
|------|-----|------|
| `nic` | `wan` | 面对校园网的接口 |
| `module` | `rjv3` | 锐捷 V3 |
| `eap-bcast-addr` / `-a` | **`1`** | 锐捷私有组播（`0` 常找不到服务器） |
| `dhcp-type` / `-d` | `2` | 认证后 DHCP |
| `version-str` | `RG-SU For Linux V1.31` | 对齐官方 Linux 客户端 |
| `service` | `internet` | 服务名 |

账号密码只放在环境文件 `/etc/ruijie/env`（权限 `600`），不进 Git。

## 仓库结构

```
openwrt-ruijie-minieap/
├── README.md
├── .env.example              # 本地部署用示例（复制为 .env）
├── install.sh                # 在路由器上安装
├── deploy.sh                 # 从电脑 SSH 推到路由器
├── uninstall.sh
├── files/
│   ├── etc/
│   │   ├── init.d/ruijie-minieap   # 开机服务 (procd)
│   │   └── ruijie/env.example
│   └── usr/bin/
│       ├── ruijie-minieap-ctl      # 启停/状态/验证/reauth
│       ├── ruijie-reauth           # 一键：认证 + DHCP（ctl reauth 别名）
│       ├── ruijie-post-auth.sh     # 认证后 WAN DHCP 续租
│       └── ruijie-net-watchdog.sh  # 掉线检测 + 自动恢复 + 持久日志
├── scripts/verify.sh
└── docs/
    ├── install.md
    └── troubleshooting.md
```

## 快速开始

### A. 从电脑一键部署（推荐）

```bash
git clone <this-repo> openwrt-ruijie-minieap
cd openwrt-ruijie-minieap
cp .env.example .env
# 编辑 .env：账号、密码、ROUTER=192.168.x.1
```

`.env` 示例（完整注释见 `.env.example`）：

```bash
ROUTER="192.168.3.1"
SSH_USER="root"
# SSH_PASS="password"          # 可选；更推荐 SSH 公钥
RUIJIE_USERNAME="学号"
RUIJIE_PASSWORD="密码"
RUIJIE_NIC="wan"
RUIJIE_EAP_BCAST="1"
RUIJIE_DHCP_TYPE="2"
RUIJIE_VERSION_STR="RG-SU For Linux V1.31"
RUIJIE_SERVICE="internet"
```

```bash
chmod +x deploy.sh install.sh
./deploy.sh --verify
```

### B. 已在路由器 SSH 里安装

```bash
# 把仓库拷到路由器后
cd openwrt-ruijie-minieap
cp files/etc/ruijie/env.example /etc/ruijie/env
vi /etc/ruijie/env          # 填账号密码
sh install.sh --start --verify
```

或：

```bash
RUIJIE_USERNAME=学号 RUIJIE_PASSWORD=密码 sh install.sh --start --verify
```

## 日常命令

### 一键重新认证 + DHCP（推荐）

断网、卡在隔离 IP（如 `172.23.x`）、或觉得 `restart` 没用时，**只跑这一条**：

```bash
ruijie-reauth
# 等价：
ruijie-minieap-ctl reauth
```

流程：

1. 干净停掉旧 minieap（避免多实例/PID 冲突）  
2. 确保 WAN 链路 up（**不会** `network reload`）  
3. 802.1x 认证，等待日志「认证成功」  
4. 多次调用 `ruijie-post-auth.sh` 做 WAN DHCP 续租（隔离网段 → 正式网段）  
5. 若进程退出则再拉起 keep-alive  
6. 检测是否在线并打印 `status`

仅续租、不再认证：

```bash
ruijie-minieap-ctl post-auth
```

### 其它

```bash
ruijie-minieap-ctl status    # 进程 + 是否在线
ruijie-minieap-ctl start     # 后台认证
ruijie-minieap-ctl stop
ruijie-minieap-ctl restart   # 只重启 minieap（可能仍停在隔离 IP）
ruijie-minieap-ctl verify    # 拉起并检测 generate_204 / ping
ruijie-minieap-ctl render-conf

/etc/init.d/ruijie-minieap enable   # 开机自启
/etc/init.d/ruijie-minieap start
/etc/init.d/ruijie-minieap stop
/etc/init.d/ruijie-minieap restart

# 掉线看门狗（install.sh 会装 cron：每 2 分钟检测、每 5 分钟收割日志）
ruijie-net-watchdog.sh once       # 离线则自动 reauth
ruijie-net-watchdog.sh snapshot   # 把现场写入持久日志
ruijie-net-watchdog.sh harvest    # 从 logread 摘 wan/minieap 行
tail -50 /overlay/ruijie-net.log  # 持久日志（重启不丢）
```

## 环境变量说明

配置文件两处模板含义相同（路由器侧与部署侧）：

| 文件 | 用途 |
|------|------|
| `files/etc/ruijie/env.example` | 装到路由器 → `/etc/ruijie/env` |
| `.env.example` | 电脑本地复制为 `.env`，供 `deploy.sh` 使用 |

含空格的值请加双引号；真实密码不要提交 Git。

### 账号与网卡

| 变量 | 默认 | 作用 |
|------|------|------|
| `RUIJIE_USERNAME` | （必填） | 校园网登录账号，一般为学号或工号，原样交给 minieap `-u`。 |
| `RUIJIE_PASSWORD` | （必填） | 校园网密码，交给 minieap `-p`。只应出现在 `/etc/ruijie/env` 或本地 `.env`。 |
| `RUIJIE_NIC` | `wan` | **执行 802.1x 的网卡名**，必须是面对校园网的口。OpenWrt 上常见 `wan`；DSA 设备不要误填 `eth0` 整口，否则 EAPOL 发不到交换机。用 `ip -br link` / `uci show network.wan` 确认。 |

### 锐捷认证行为

| 变量 | 默认 | 作用 |
|------|------|------|
| `RUIJIE_EAP_BCAST` | `1` | 对应 minieap **`-a`**：EAPOL Start 的目的地址类型。`0`=标准以太网广播；**`1`=锐捷私有组播**。暨南等多数锐捷环境必须为 `1`，否则会一直「正在查找认证服务器」。 |
| `RUIJIE_DHCP_TYPE` | `2` | 对应 minieap **`-d` / dhcp-type**：何时向校园网要 IP。`0` 不用 DHCP；`1` 二次认证；**`2` 认证成功后再 DHCP**（推荐，对齐官方「认证后获取」）；`3` 认证前先 DHCP。认证后 IP 段变化（如从隔离段换到 `172.20.x`）是正常现象。 |
| `RUIJIE_SERVICE` | `internet` | 对应 minieap **`--service`**：学校侧配置的「服务名」。部分学校区分校园网/运营商；官方客户端可用 `-s` / `-l` 查看。不确定时先试 `internet`。 |
| `RUIJIE_VERSION_STR` | `RG-SU For Linux V1.31` | 对应 **`--version-str`**：客户端版本声明，会打进锐捷私有字段。服务器可能校验，需与学校下发的 RG-SU 版本接近。暨南官方 Linux 学生包为 **1.31**。字符串含空格，配置时必须加引号。 |
| `RUIJIE_FAKE_SERIAL` | `OPENWRT-001` | 对应 **`--fake-serial`**：锐捷可能采集硬盘序列号。路由器没有真实硬盘时填固定字符串即可，避免 minieap 警告或校验异常。 |
| `RUIJIE_HEARTBEAT` | `60` | 对应 minieap **`-e` / heartbeat**：认证成功后 **Keep-Alive 间隔（秒）**，维持会话、减少被踢。常见 30～60。 |
| `RUIJIE_MODULE` | `rjv3` | minieap 数据包插件。**`rjv3`** 实现锐捷 V3/V4 私有算法，本仓库默认且已在暨南验证。一般不要改。 |

### 安装与部署（可选）

| 变量 | 默认 | 作用 |
|------|------|------|
| `MINIEAP_IPK_URL` | 空 / install 内置 arch 默认 | 当 `opkg install minieap` 失败时，从该 URL 下载 `.ipk` 安装。须匹配 **CPU 架构**（如 `mipsel_24kc`）和 **固件年代**；过新的包在老 musl 上会报 `__time64` 等符号错误。 |
| `ROUTER` | `192.168.1.1` | **仅 `.env` / deploy.sh**：路由器管理 IP，SSH 目标。不会写入路由器认证配置。 |
| `SSH_USER` | `root` | **仅 deploy.sh**：SSH 用户名。 |
| `SSH_PORT` | `22` | **仅 deploy.sh**：SSH 端口。 |
| `SSH_PASS` | （空） | **仅 deploy.sh**：SSH 密码；需本机 `sshpass`。更推荐配置 SSH 公钥后留空。 |

### 与 minieap 命令行对照

| 环境变量 | minieap 选项 |
|----------|----------------|
| `RUIJIE_USERNAME` | `-u` |
| `RUIJIE_PASSWORD` | `-p` |
| `RUIJIE_NIC` | `-n` |
| `RUIJIE_MODULE` | `--module` |
| `RUIJIE_EAP_BCAST` | `-a` |
| `RUIJIE_DHCP_TYPE` | `-d` |
| `RUIJIE_HEARTBEAT` | `-e` |
| `RUIJIE_SERVICE` | `--service` |
| `RUIJIE_VERSION_STR` | `--version-str` |
| `RUIJIE_FAKE_SERIAL` | `--fake-serial` |

暨南宿舍口已验证的一组取值：`NIC=wan`，`EAP_BCAST=1`，`DHCP_TYPE=2`，`SERVICE=internet`，`VERSION_STR=RG-SU For Linux V1.31`。

## 掉线看门狗（ruijie-net-watchdog）

`install.sh` / `deploy.sh` 会一并安装：

| 项 | 说明 |
|----|------|
| 脚本 | `/usr/bin/ruijie-net-watchdog.sh` |
| cron | 每 **2 分钟** `once`；每 **5 分钟** `harvest` |
| 持久日志 | `/overlay/ruijie-net.log`（约 200KB 滚动） |

离线时自动：写 snapshot → **`ruijie-minieap-ctl reauth`**（认证 + DHCP + 在线检测）。  
用于覆盖：会话掉线、卡在隔离 IP（如 `172.23.x`）未 renew 到正式网段等情况。

## 原理（简要）

1. 交换机对 WAN 口做 **802.1x**，需锐捷私有 EAP 扩展（RJv3）。  
2. `minieap` 在 `wan` 上发 EAPOL，账号校验成功后可选 DHCP。  
3. OpenWrt **NAT/masquerade** 把 LAN/WiFi 流量从已认证 WAN 出去。  
4. 认证前常为 **隔离网段**（如 `172.23.x`）；认证后必须 **DHCP 续租** 到正式段（如 `172.20.x`）。  
5. **`ruijie-post-auth.sh`** 只做第 4 步；**`ruijie-reauth`** = 第 2 步 + 第 4 步 + 检测。  
6. 裸 `restart` 往往只做第 2 步，所以会出现「日志认证成功但上不了网」。

官方 Linux 客户端（RG-SU）仅 x86/x64；路由器 mips 用 minieap 等价实现。

## 依赖

- OpenWrt / ImmortalWrt / iStoreOS 等  
- `minieap`（`install.sh` 会尝试 opkg 或 `MINIEAP_IPK_URL`）  
- `curl` 或 `wget`（安装 ipk / 连通性检测）  
- 防火墙 WAN 区 **IP 动态伪装 (masq)** 已开启（默认一般有）

**注意：** 过新的 minieap ipk 可能因 musl `time64` 与老固件不兼容。R21 / 21.02 时代可优先：

```
https://downloads.immortalwrt.org/releases/21.02.7/packages/mipsel_24kc/packages/minieap_0.93-3_mipsel_24kc.ipk
```

按自己的 `DISTRIB_ARCH` 更换路径。

## 安全

- 不要把含真实密码的 `.env` / `/etc/ruijie/env` 提交到 Git。  
- 仅使用自己有权使用的校园网账号。  
- 遵守学校网络管理规定。

## License

MIT
