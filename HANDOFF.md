# de_GWD 双端安装修复交接（2026-09-08）

## 目标与范围

以 `jacyl4/de_GWD` 上游提交 `a689d1144c21ecd032a767d202c5d2dbe83db29f` 为基底，在独立分支 `codex/upstream-dual-repair` 修复 Client/Server 安装可靠性。范围来自本轮确认：保留原功能和交互；stock Debian 内核可安装，不强制 Zabbly；运行时不依赖 `jacyl4/de_GWD`；支持 curl/wget 入口；Client 用 vm1242 节点做 live 验收；Server 做静态和回归验证，真实 Server/ACME 延后。

## 工作树与发布状态

- 工作树：`/Users/stuinx/Documents/ChatGPT/de_GWD 2/upstream-repair-20260908`
- 分支：`codex/upstream-dual-repair`
- 当前基底仍为上游提交；修改尚未提交/推送。
- 当前 origin 仍是本地 `stuinx-deGWD-fix-work` 路径，发布前需要切换到用户指定的 `stuinx/deGWD` 远端并推送该分支。
- 临时安装源只用于 live 测试：vm1226 的 `/tmp/degwd-repair`，HTTP `127.0.0.1:18765`，`repo.env` 中记录了本地 `DE_GWD_REPO_BASE` 和 `DE_GWD_REF=local`；这不是公开发布证明。

## 已修改

- Client/Server：仓库基址与 ref 参数化（默认 `stuinx/deGWD` 的修复分支）、curl/wget 入口、atomic 下载、GitHub 源回退、SHA256 预检和缓存校验、APT 锁等待与失败传播。
- Client：启动前预取并校验 geoip/geosite/chnroute/DNS 规则；Docker GPG 多源回退；V2 节点解析增加公共 DNS 回退；不强制安装/切换 Zabbly；移除 TProxy 入站 TCP Fast Open。
- Client TProxy：新增 `/opt/de_GWD/nftables/tproxy_route.sh`，以重试和状态校验安装 table 220 与 `fwmark 0x9` 规则；nftables 服务等待 `network-online.target`，避免早期网卡临时名写入 flowtable 导致重启后 nftables 失败。
- 证书/更新/UI：CF_Key/CF_Email 子进程导出与错误传播；更新和凌晨脚本使用统一仓库 helper、临时文件和原子替换；UI 版本链接改为 `stuinx/deGWD`；`version.php` 不再运行时读取远端。
- `resource/client/Archive.zip` 已重建并更新 SHA256。
- `tests/test_install_reliability.py` 现有 20 项回归测试。

## 静态验证

- `python3 -m unittest -v tests/test_install_reliability.py`：20/20 通过。
- `bash -n client server resource/client/ui-script/ui-installCER resource/client/ui-script/ui-NodeOne resource/client/ui-script/ui_4am resource/client/ui-script/ui-autoUpdateHour`：通过。
- `git diff --check`：通过。
- 回归覆盖：下载失败不发布部分响应、镜像回退、空/缺失校验值拒绝、CF 变量导出、ACME 失败传播、共享 ref、Docker/DNS 回退、TProxy policy route 持久化、Archive 成员一致性等。

## vm1226 Client live 证据

测试机：`10.0.0.226`，PVE VM 1226；使用 `init` 快照恢复后安装；节点取自 vm1242：`dd.stuinx.com:2096`，地址与证书域名一致。安装输入使用本机 `10.0.0.226`、网关 `10.0.0.254`、DoH `/dq`、节点路径 `/7b48a6` 和 vm1242 提供的 UUID（不在此文件记录凭证）。

- 初始状态：Debian 12 bookworm，stock `6.1.0-51-amd64`，无 de_GWD 服务。
- 前置资源 curl 预检通过；首轮 Repo Download 因临时源漏建 `local/` 映射而硬失败，补齐映射后重跑通过。这是测试源准备错误，安装器按设计停止。
- Pi-hole 首次拉取受当前网络 Docker Hub/CloudFront layer reset 影响而硬失败；从 vm1242 导入已有 `pihole/pihole:latest` 后继续，证明失败不会假成功。该镜像下载边界仍取决于外部 registry 网络。
- 最终安装输出 `de_GWD Installed`；SmartDNS、mosdns、Pi-hole、vtrui、Nginx、php7.4-FPM、Docker、cron 全部 active；Pi-hole container healthy。
- 资源 SHA256 与受控测试源一致：geoip、geosite、IPchnroute、Domains.chn/apple/games、99-bogus-nxdomain。
- `nginx -t`、`jq empty /opt/de_GWD/vtrui/config.json`、`nft -c -f /opt/de_GWD/nftables/nftables` 通过。
- 重启后运行 stock `6.1.0-52-amd64`，无 Zabbly 内核；`ip rule` 有 `100: from all fwmark 0x9 lookup 220`，table 220 为 `local default dev lo`；flowtable 使用 `eth0,ifb4eth0`；nftables/vtrui/DNS/Nginx/Docker 全 active。
- 本机 DNS：`dd.stuinx.com` 和 `example.com` 均能由 `127.0.0.1:53` 解析；透明 TCP `curl https://www.gstatic.com/generate_204` 返回 HTTP 204。UDP 的透明路径已由 nft/vtrui socket 和 `ip route get ... mark 9` 验证，但没有可控的公网 UDP echo 端点，不能把外部 UDP 回包成功写成已验收。
- vtrui 仍是原逻辑的 TProxy `dokodemo-door` 9896 入站；没有新增 HTTP/SOCKS 显式代理端口，因此显式 proxy 测试不作为通过条件。
- 已安装运行时搜索未发现 `jacyl4/de_GWD`；仍保留 `jacyl4/chnroute` 规则源，属于用户允许的其他仓库依赖。

## 尚未完成/边界

- Server 尚未在真实主机安装；只完成静态和回归验证。真实 CF ACME、Server 节点链路、Server 公网端口和双端端到端仍待单独验收。
- 没有执行真实 ACME 签发/续期，也没有记录任何凭证。
- Docker 镜像在线下载仍受目标网络影响；安装器会在镜像不可得时硬失败，不会带着缺失 Pi-hole 继续报告成功。
- 需要在提交前检查 `git diff`、更新远端、提交并推送 `codex/upstream-dual-repair`；随后若用户要求，再提供双端在线入口命令。

## 恢复与注意事项

- PVE：`ssh -i ~/.ssh/stuinxo -p 11122 root@10.0.0.7`；vm1226 的 `init` 快照可用于重复验证。
- 不要删除 apt/dpkg 锁；先查持锁进程并等待。
- 不要把 `de_GWD Installed`、进程 active 或单个 HTTP 200 当成透明路由验收；必须同时检查服务、配置、nft 校验、policy route、重启恢复和实际路径。
- 不在交接或提交中记录密码、Token、Cookie、私钥或完整凭证。
