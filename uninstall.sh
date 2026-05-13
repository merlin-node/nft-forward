#!/bin/bash
# nft-forward 卸载脚本

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

msg()  { echo -e "${GREEN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then
    echo "需要 root 权限"
    exit 1
fi

echo ""
warn "即将卸载 nft-forward,会:"
echo "  - 停止并删除 systemd 服务"
echo "  - 清除本脚本创建的 nftables 表(nft_forward / nft_forward6)"
echo "  - 删除 /usr/local/bin/nft-forward"
echo ""
read -rp "是否保留配置文件 /etc/nft-forward ? [Y/n]: " keep
read -rp "确认卸载? [y/N]: " yn
[[ "$yn" =~ ^[Yy]$ ]] || { echo "取消"; exit 0; }

msg "停止服务..."
systemctl stop nft-forward-ddns.timer 2>/dev/null || true
systemctl stop nft-forward-ddns.service 2>/dev/null || true
systemctl stop nft-forward.service 2>/dev/null || true
systemctl disable nft-forward-ddns.timer 2>/dev/null || true
systemctl disable nft-forward.service 2>/dev/null || true

msg "清除 nftables 表..."
nft delete table ip nft_forward 2>/dev/null || true
nft delete table ip6 nft_forward6 2>/dev/null || true

msg "删除文件..."
rm -f /etc/systemd/system/nft-forward.service
rm -f /etc/systemd/system/nft-forward-ddns.service
rm -f /etc/systemd/system/nft-forward-ddns.timer
rm -f /usr/local/bin/nft-forward
rm -f /usr/local/bin/zf
rm -f /etc/nftables-forward.conf
rm -f /etc/sysctl.d/99-nft-forward.conf

systemctl daemon-reload

if [[ ! "$keep" =~ ^[Yy]$ ]] && [[ -n "$keep" ]]; then
    rm -rf /etc/nft-forward
    rm -f /var/log/nft-forward.log
    msg "配置和日志已删除"
else
    msg "已保留 /etc/nft-forward 和 /var/log/nft-forward.log"
fi

msg "卸载完成"
