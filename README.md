# Argo-Script

基于 [0xdabiaoge/singbox-lite](https://github.com/0xdabiaoge/singbox-lite) 的 VLESS-WS + Argo 安装入口。安装时下载固定上游提交，在本机应用小范围补丁；本仓库不复制上游完整脚本。感谢上游作者，原功能和依赖安装逻辑来自上游。

上游提交：`f5143fe49256ae71cd013b2717ea83cfa3a8b8ec`。

## 两种隧道安装

适用于 root 权限 Linux（Debian/Ubuntu/Alpine）。不是 Windows 原生安装脚本；Windows 请在 Linux 虚拟机中测试。先安装 curl；精简 Alpine 可先运行 `apk add --no-cache curl`。

### 临时隧道 + auto

```sh
curl -fLsS https://raw.githubusercontent.com/zhangx16/Argo-Script/main/install.sh -o /tmp/argo-auto-install.sh
sh /tmp/argo-auto-install.sh --mode temp --transport auto
```

按提示输入内部监听端口、WS 路径和节点名称。临时域名由 Cloudflare 分配，隧道重建后会变化，需重新导入链接。

### Token 固定隧道 + auto

```sh
curl -fLsS https://raw.githubusercontent.com/zhangx16/Argo-Script/main/install.sh -o /tmp/argo-auto-install.sh
sh /tmp/argo-auto-install.sh --mode fixed --transport auto
```

按提示输入内部端口、WS 路径、Tunnel Token、绑定域名和名称。在 Cloudflare Tunnel 的 Published application/Public Hostname 中配置：

- Hostname：例如 `main.example.com`
- Service：`http://127.0.0.1:内部端口`

Token 仅输入服务器交互提示，不要写进公开仓库或分享链接。避免把同一个 Tunnel Token 分配给配置不同的测试实例，否则 Cloudflare 可能把请求分配到不同 connector，干扰实验。

## auto 与固定隧道是独立选项

`--mode temp|fixed` 选择临时/固定域名；`--transport auto|http2|quic` 选择服务器到 Cloudflare 的传输。两种隧道均支持 auto。

auto 优先尝试 QUIC，无法建立 UDP 连接时回退 HTTP/2，不是延迟测速后自动择优，也不保证更快。服务器需允许出站 UDP/TCP 7844；无需为了 Argo 对公网开放内部 WS 端口。

## 后续管理与对照实验

```sh
sb-argo-auto
```

传输设置持久化在 `/usr/local/etc/sing-box/argo-transport`，守护恢复隧道时也会读取。只修改设置不会立即重启已有进程：

```sh
printf 'http2\n' > /usr/local/etc/sing-box/argo-transport
# 然后 sb-argo-auto → Argo 隧道节点 → 重启目标隧道
```

改回 auto：

```sh
printf 'auto\n' > /usr/local/etc/sing-box/argo-transport
# 然后通过同一菜单重启目标隧道
```

设置作用于此管理器下一次启动的所有 Argo 节点。旧版 sb 或其他面板的守护不会读取它；同一节点只保留一个管理器负责重启，避免参数被其他守护覆盖。不自动改动其他面板的守护任务。

反复运行安装器会新增节点，不是切换已有节点的命令。新旧安装共享上游的 `/usr/local/etc/sing-box` 配置目录；安装前自动备份配置至 `/usr/local/lib/argo-auto/backup-*`。先在独立测试机验证。已安装核心保留；首次安装使用上游固定核心版本策略。

客户端继续使用优选域名作为连接地址，TLS SNI 与 WS Host 保持为实际隧道域名。例：地址 `hk.031216.xyz`、443、TLS 开启、SNI/Host `main.example.com`。分享链接不自动替换为个人优选域名，请导入后修改地址字段。

保持同一入口、目标网址、客户端、UUID、路径及 Early Data，分别测 HTTP/2 → auto → HTTP/2。记录成功率、延迟中位数、下载速度、空闲断线情况；ping 不等于完整节点延迟。确认日志出现 `protocol=quic`，才能把 auto 组视为 QUIC 组。

官方说明：[cloudflared 传输参数](https://developers.cloudflare.com/tunnel/reference/run-parameters/)。TLS 和 WS Early Data 沿用上游配置。本扩展不会关闭 TLS、调整证书校验或对现有节点自动切换协议。

## 验证范围

本仓库提供 Bash 语法与补丁结构检查。生产环境安装依赖、Token 授权以及服务器网络条件仍需在目标 Linux 上验证；并未承诺所有上游功能或未来版本兼容。上游引用固定，管理器内的脚本自更新入口被禁用，避免自动覆盖 transport 补丁；更新请重新审查安装器。
