#!/bin/bash
# nft-forward 卸载脚本

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

msg()  { echo -e "${GREEN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

# 自适应分割线
term_width() {
    local w
    w=$(tput cols 2>/dev/null || echo 60)
    (( w < 40 )) && w=40
    (( w > 80 )) && w=80
    echo "$w"
}
hr() {
    local color="${1:-$YELLOW}" w
    w=$(term_width)
    printf "${color}%${w}s${NC}\n" '' | tr ' ' '='
}

if [[ $EUID -ne 0 ]]; then
    echo "需要 root 权限"
    exit 1
fi

echo ""
hr "$YELLOW"
warn "即将卸载 nft-forward,会:"
hr "$YELLOW"
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
rm -f /etc/logrotate.d/nft-forward
rm -f /usr/local/bin/nft-forward
rm -f /usr/local/bin/zf
rm -f /etc/nftables-forward.conf
rm -f /etc/sysctl.d/99-nft-forward.conf

systemctl daemon-reload

if [[ ! "$keep" =~ ^[Yy]$ ]] && [[ -n "$keep" ]]; then
    rm -rf /etc/nft-forward
    rm -f /var/log/nft-forward.log /var/log/nft-forward.log.*
    msg "配置和日志已删除"
else
    msg "已保留 /etc/nft-forward 和 /var/log/nft-forward.log"
fi

echo ""
hr "$GREEN"
msg "卸载完成"
hr "$GREEN"
