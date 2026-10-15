# ddns-dynv6

Dynamic DNS updater for dynv6.com - 自动更新 dynv6 域名的 IPv6 地址解析。

## 功能

- 自动检测指定网卡的 IPv6 地址变化
- 通过 NetworkManager dispatcher 实时响应网络事件
- systemd timer 作为 fallback 机制
- debconf 交互式安装配置
- 支持多个域名（规划中）

## 系统要求

- Ubuntu 20.04+ / Debian 11+
- NetworkManager（推荐，但非必须）
- curl, iproute2

## 安装

### 从 deb 包安装

```bash
sudo dpkg -i ddns-dynv6_0.1.0_all.deb
```

安装过程中会交互式询问：
- 网卡名称（如 `eno1`）
- dynv6 Token
- 要更新的域名

### 从源码构建

```bash
./build.sh
```

构建产物在 `build/` 目录下。

或手动构建：

```bash
dh_clean && dpkg-buildpackage -us -uc -b
```

## 配置

配置文件位于 `/etc/ddns-dynv6.conf`：

```bash
INTERFACE="eno1"
TOKEN="your-token-here"
DOMAINS="example.dynv6.net"
NETMASK="128"
```

重新配置：

```bash
sudo dpkg-reconfigure ddns-dynv6
```

## 使用

### 手动触发更新

```bash
sudo systemctl start ddns-dynv6.service
```

### 查看日志

```bash
journalctl -u ddns-dynv6.service
```

### 查看状态

```bash
systemctl status ddns-dynv6.service
systemctl status ddns-dynv6.timer
```

## 工作原理

```
┌─────────────────────────────────────────────────────────┐
│                    IPv6 地址变化                         │
└─────────────────────────────────────────────────────────┘
                           │
           ┌───────────────┴───────────────┐
           ▼                               ▼
┌─────────────────────┐         ┌─────────────────────┐
│ NM dispatcher       │         │ systemd timer       │
│ (实时响应)          │         │ (每10分钟检查)      │
└─────────────────────┘         └─────────────────────┘
           │                               │
           └───────────────┬───────────────┘
                           ▼
┌─────────────────────────────────────────────────────────┐
│               ddns-dynv6.service                        │
│  1. 检测 IPv6 地址                                      │
│  2. 对比上次记录                                        │
│  3. 调用 dynv6 API 更新                                 │
└─────────────────────────────────────────────────────────┘
```

## 卸载

```bash
sudo apt remove ddns-dynv6
```

## 开发

### 项目结构

```
ddns-dynv6/
├── debian/           # Debian 打包配置
├── src/              # 主脚本
├── systemd/          # systemd 服务/定时器
├── dispatcher/       # NetworkManager dispatcher
├── Makefile          # 构建脚本
├── README.md
└── LICENSE
```

### 构建 deb 包

```bash
make deb
```

## License

MIT License