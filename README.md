# 寒月
* 具备流量整形加速的旁路网关
* 仅供学习与研究，不支持机场的双端自建方案

* 基于性能考量，尽量避免使用虚拟交换


[![Telegram](https://cdn.jsdelivr.net/gh/Patrolavia/telegram-badge@8fe3382b3fd3a1c533ba270e608035a27e430c2e/chat.svg)](https://t.me/de_GWD_DQ)  


## 安装测试分支

本次定制版发布在 `stuinx/deGWD` 的 `codex/install-test-20260913` 分支，适用于 amd64/arm64 的 Debian 12（bookworm）测试机。请先在全新快照或可回滚环境测试。

Server：

```bash
apt-get update && apt-get install -y curl
curl -fsSL https://raw.githubusercontent.com/stuinx/deGWD/codex/install-test-20260913/server -o /tmp/de-gwd-server
bash /tmp/de-gwd-server
```

Client：

```bash
apt-get update && apt-get install -y curl
curl -fsSL https://raw.githubusercontent.com/stuinx/deGWD/codex/install-test-20260913/client -o /tmp/de-gwd-client
bash /tmp/de-gwd-client
```

客户端默认使用清华大学 HTTPS Debian/Docker 镜像；GitHub 访问受限时可设置 HTTPS 下载代理。也可在执行前覆盖 `GWD_REPO` 和 `GWD_REF`，用于测试其他分支：

```bash
GWD_GITHUB_PROXY=https://你的下载代理 \
GWD_DEBIAN_MIRROR=https://mirrors.tuna.tsinghua.edu.cn \
GWD_DOCKER_SOURCE=https://mirrors.tuna.tsinghua.edu.cn/docker-ce \
bash /tmp/de-gwd-client
```

安装脚本会把定制分支写入更新配置；Web UI 保存更新命令时会先下载、语法检查并原子替换更新脚本，自动更新也继续使用该分支。

![de_GWD 0](https://raw.githubusercontent.com/stuinx/deGWD/codex/install-test-20260913/resource/screenshot/0.png)

### Server 菜单扩展

安装完成后，Server 菜单新增以下入口：

- `HAProxy 多条转发管理`：独立维护多个 TCP 转发，支持域名、IPv4 和 `[IPv6]:端口` 目标，并在变更前后校验配置。
- `Xray 多协议管理`：独立于原有节点配置添加 VLESS、VMess、Trojan、Shadowsocks（TLS 支持 TCP/WebSocket）监听。
- `RproxyS 反向隧道`：创建 portal、添加或删除多个 TCP/UDP 映射，并生成 client 连接参数文件。

证书菜单按完整主机名申请和部署证书，支持 `a.b.example.com` 等多级域名；DNS-01 与 Webroot HTTP-01 均保留原有入口。

客户端 Web UI 的“预定义分流”现在可以分别为 Claude、Gemini、Grok、Wikipedia、Reddit、GitHub、Discord、Telegram、X/Twitter 以及 OpenAI、YouTube 选择节点或默认代理；Netflix、HDH、TVB、Bahamut 旧分流会在恢复配置时清理。

![de_GWD 1](https://raw.githubusercontent.com/stuinx/deGWD/codex/install-test-20260913/resource/screenshot/1.png)
![de_GWD 2](https://raw.githubusercontent.com/stuinx/deGWD/codex/install-test-20260913/resource/screenshot/2.png)
![de_GWD 3](https://raw.githubusercontent.com/stuinx/deGWD/codex/install-test-20260913/resource/screenshot/3.png)
![de_GWD 4](https://raw.githubusercontent.com/stuinx/deGWD/codex/install-test-20260913/resource/screenshot/4.png)
![de_GWD 5](https://raw.githubusercontent.com/stuinx/deGWD/codex/install-test-20260913/resource/screenshot/5.png)

## Manual:
[Deepwiki 自动生成的文档](https://deepwiki.com/jacyl4/de_GWD)    

## Thanks to
* [ XTLS/Xray-core ](https://github.com/XTLS/Xray-core)
* [ coredns/coredns ](https://github.com/coredns/coredns)
* [ pymumu/smartdns ](https://github.com/pymumu/smartdns)
* [ IrineSistiana/mosdns ](https://github.com/IrineSistiana/mosdns)
* [ m13253/dns-over-https ](https://github.com/m13253/dns-over-https)
* [ pi-hole/docker-pi-hole ](https://github.com/pi-hole/docker-pi-hole)
* [ mmotti/pihole-regex ](https://github.com/mmotti/pihole-regex)
* [ Loyalsoldier/v2ray-rules-dat ](https://github.com/Loyalsoldier/v2ray-rules-dat)
* [ makotom/cfspeed ](https://github.com/makotom/cfspeed)
* [ mzz2017/lkl-haproxy ](https://github.com/mzz2017/lkl-haproxy)
* [ zabbly/linux ](https://github.com/zabbly/linux)
* [ xanmod/linux ](https://github.com/xanmod/linux)
* [ tsl0922/ttyd ](https://github.com/tsl0922/ttyd)
* [ mikefarah/yq ](https://github.com/mikefarah/yq)
* [ nyanmisaka/jellyfin ](https://hub.docker.com/r/nyanmisaka/jellyfin)
* [ dani-garcia/vaultwarden ](https://github.com/dani-garcia/vaultwarden)

## Stargazers over time
[![Stargazers over time](https://starchart.cc/jacyl4/de_GWD.svg)](https://starchart.cc/jacyl4/de_GWD)

[![Powered by DartNode](https://dartnode.com/branding/DN-Open-Source-sm.png)](https://dartnode.com "Powered by DartNode - Free VPS for Open Source")
