# de_GWD 定制版安装测试交接

## 目标与授权

在上游 `jacyl4/de_GWD` 的 `a689d1144c21ecd032a767d202c5d2dbe83db29f` 基础上完成：国内 client 安装优化、server RproxyS、server 独立 Xray 多协议菜单、HAProxy 多条转发、独立站点分流、双端多级域名证书。用户已授权推送 GitHub，并选择 `stuinx/deGWD`；计划新建 `codex/install-test-20260913` 分支供安装测试。

## 已完成与证据

- 工作目录：当前 Git 仓库。定制修改尚未提交；以 `git status` 和差异为准。
- 本地分流回归 9 项通过；实际 Xray 核心通过多协议配置校验和本机反向隧道转发测试；HAProxy 本机配置校验通过。
- 证书流程、服务回滚和下载校验使用隔离目录及模拟服务测试，未在 Debian 双端实机安装。
- 当前已核验 GitHub 的 `stuinx/deGWD` 可写，远端 `main` 为 `9436efd73fce909930ebd7ec8f9e7861f642ae67`。尚未推送本次定制分支。

## 当前工作与待完成

1. 补齐独立脚本安装及自动更新的定制仓库地址，避免回到上游 UI。
2. 修复客户端更新下载准备流程及 Docker APT 公钥格式。
3. 展开当前 sparse checkout，重新打包 UI、校验校验和，补充安装更新回归。
4. 提交并推送测试分支，核对远端提交及 raw 文件，提供安装命令。

## 文件与验证

主要修改：`client`、`server`、`README.md`、`resource/client/Archive.zip` 及其 SHA-256、`ui-NodeSM`、`ui-installCER`、`ui-installDocker`、更新/恢复脚本、分流页面及 `routing-presets.json`、`tests/test_presets.py`。

仓库内验证：`python3 -m unittest discover -s tests -v`、对修改的 Shell/PHP 脚本运行语法检查。运行时测试当前在工作区上一级 `test_server_runtime.py`、`test_reverse_flow.py`、`test_haproxy.py`、`test_certificates.py`、`test_download.py`、`test_xray_rollback.py`，从任务目录运行。反向隧道测试依赖先完成 server runtime 测试。

## 注意与恢复

- 不执行本机 Linux 安装器；当前主机是 macOS。Debian 安装、重启恢复、真实 DNS/ACME 签发尚待测试。
- 不重用其他 de_GWD/dex 历史分支判断；进入后先核验 Git 状态和远端。
- 原工作区采用 partial/sparse clone，旧导出的源码包不包含所有上游资源；不要将它作为完整离线安装包。
- 不提交 `tests/__pycache__`。不含任何密码、Token 或私钥。
