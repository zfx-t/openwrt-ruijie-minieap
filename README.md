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
│   └── usr/bin/ruijie-minieap-ctl  # 启停/状态/验证
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

`.env` 示例：

```bash
ROUTER=192.168.3.1
SSH_USER=root
# SSH_PASS=password          # 可选；更推荐 SSH 公钥
RUIJIE_USERNAME=学号
RUIJIE_PASSWORD=密码
RUIJIE_NIC=wan
RUIJIE_EAP_BCAST=1
RUIJIE_DHCP_TYPE=2
RUIJIE_VERSION_STR=RG-SU For Linux V1.31
RUIJIE_SERVICE=internet
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

```bash
ruijie-minieap-ctl status    # 进程 + 是否在线
ruijie-minieap-ctl start     # 后台认证
ruijie-minieap-ctl stop
ruijie-minieap-ctl restart
ruijie-minieap-ctl verify    # 拉起并检测 generate_204 / ping
ruijie-minieap-ctl render-conf

/etc/init.d/ruijie-minieap enable   # 开机自启
/etc/init.d/ruijie-minieap start
/etc/init.d/ruijie-minieap stop
/etc/init.d/ruijie-minieap restart
```

## 环境变量说明

| 变量 | 默认 | 说明 |
|------|------|------|
| `RUIJIE_USERNAME` | （必填） | 学号/账号 |
| `RUIJIE_PASSWORD` | （必填） | 密码 |
| `RUIJIE_NIC` | `wan` | 认证网卡 |
| `RUIJIE_EAP_BCAST` | `1` | 0 标准 / 1 锐捷组播 |
| `RUIJIE_DHCP_TYPE` | `2` | 0 无 / 1 二次 / 2 认证后 / 3 认证前 |
| `RUIJIE_SERVICE` | `internet` | 服务名 |
| `RUIJIE_VERSION_STR` | `RG-SU For Linux V1.31` | 客户端版本串 |
| `RUIJIE_FAKE_SERIAL` | `OPENWRT-001` | 伪造硬盘序列号 |
| `RUIJIE_HEARTBEAT` | `60` | 心跳秒 |
| `RUIJIE_MODULE` | `rjv3` | minieap 插件 |
| `MINIEAP_IPK_URL` | 见 install.sh | 无 opkg 包时离线下载 |

## 原理（简要）

1. 交换机对 WAN 口做 **802.1x**，需锐捷私有 EAP 扩展（RJv3）。  
2. `minieap` 在 `wan` 上发 EAPOL，账号校验成功后可选 DHCP。  
3. OpenWrt **NAT/masquerade** 把 LAN/WiFi 流量从已认证 WAN 出去。  
4. 网页 Portal 劫持有时仍存在，但 **真正放行的是 802.1x**（本仓库路径）。

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
