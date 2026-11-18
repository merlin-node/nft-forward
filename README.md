# nft-forward

基于 nftables 的端口转发管理脚本(Debian 13),可选 realm 用户态转发。

## 安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/merlin-node/nft-forward/main/install.sh)
```

没有 curl 就用 wget:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/merlin-node/nft-forward/main/install.sh)
```

GitHub 直连慢可以走镜像(安装脚本内部下载也会自动回退镜像):

```bash
bash <(curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/merlin-node/nft-forward/main/install.sh)
```

需要 root,非 root 用户在前面加 `sudo`。不再依赖 unzip。

## 使用

```bash
zf
```

主菜单上下两块结构一致,都是 查看 / 添加 / 删除 / 管理:

- **nftables 转发(1-4)**:内核 DNAT,性能最好。域名目标由后台定时器自动刷新,IPv6 开关和 DDNS 间隔在 `4` 里
- **realm 转发(5-8)**:用户态转发,目标域名由 realm 实时解析,支持 IPv6 目标。第一次添加 realm 规则时会提示安装,安装/更新/日志/卸载在 `8` 里

两边端口不能重复;添加、删除只会重载自己这一边,不影响另一边的连接。

## 更新

进菜单按 `12` 即可在线更新(规则和设置保留)。

## 卸载

进菜单按 `13` 即可一键卸载。
