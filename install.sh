#!/bin/bash
# nft-forward 安装脚本
# 用法: sudo bash install.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

msg()  { echo -e "${GREEN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*"; }

# 自适应分割线
term_width() {
    local w
    w=$(tput cols 2>/dev/null || echo 60)
    (( w < 40 )) && w=40
    (( w > 80 )) && w=80
    echo "$w"
}
hr() {
    local color="${1:-$GREEN}" w
    w=$(term_width)
    printf "${color}%${w}s${NC}\n" '' | tr ' ' '='
}

if [[ $EUID -ne 0 ]]; then
    err "需要 root 权限,请用 sudo 运行"
    exit 1
fi

# 检查系统
if ! grep -qi debian /etc/os-release 2>/dev/null; then
    warn "本脚本针对 Debian 设计,其他系统可能有兼容问题"
    read -rp "继续? [y/N]: " yn
    [[ "$yn" =~ ^[Yy]$ ]] || exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

msg "1/5 安装依赖..."
apt-get update -qq
apt-get install -y -qq nftables iproute2 >/dev/null

msg "2/5 安装主程序到 /usr/local/bin/nft-forward..."
install -m 755 "$SCRIPT_DIR/nft-forward" /usr/local/bin/nft-forward

# 创建短命令 zf
ln -sf /usr/local/bin/nft-forward /usr/local/bin/zf

msg "3/5 创建配置目录..."
mkdir -p /etc/nft-forward
chmod 700 /etc/nft-forward

msg "4/5 安装 systemd 服务..."

# 开机加载规则的服务
cat > /etc/systemd/system/nft-forward.service <<'EOF'
[Unit]
Description=nft-forward apply rules
Documentation=nft-forward
After=network-online.target
Wants=network-online.target
Before=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/nft-forward apply
ExecReload=/usr/local/bin/nft-forward apply
ExecStop=/usr/sbin/nft delete table ip nft_forward
ExecStop=-/usr/sbin/nft delete table ip6 nft_forward6

[Install]
WantedBy=multi-user.target
EOF

# DDNS 更新服务
cat > /etc/systemd/system/nft-forward-ddns.service <<'EOF'
[Unit]
Description=nft-forward DDNS update
After=nft-forward.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nft-forward ddns
EOF

# DDNS 定时器
cat > /etc/systemd/system/nft-forward-ddns.timer <<'EOF'
[Unit]
Description=nft-forward DDNS update timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=nft-forward-ddns.service

[Install]
WantedBy=timers.target
EOF

msg "5/6 安装日志轮转配置..."
cat > /etc/logrotate.d/nft-forward <<'EOF'
/var/log/nft-forward.log {
    size 10M
    rotate 3
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF

msg "6/6 启用服务..."
systemctl daemon-reload
systemctl enable nft-forward.service >/dev/null 2>&1
systemctl enable nft-forward-ddns.timer >/dev/null 2>&1
systemctl start nft-forward-ddns.timer

# 启用 nftables.service(系统默认的持久化方式,但我们用独立 table 不冲突)
systemctl enable nftables.service >/dev/null 2>&1 || true

echo ""
hr "$GREEN"
echo -e "${GREEN}  安装完成!${NC}"
hr "$GREEN"
echo ""
echo -e "  使用方法: 输入 ${GREEN}zf${NC} 回车进入菜单"
echo -e "             也可以输入 ${GREEN}nft-forward${NC} (完整命令名)"
echo ""
echo "  常用命令:"
echo "    zf                  # 交互菜单"
echo "    zf list             # 查看规则"
echo "    zf apply            # 重新应用规则"
echo "    zf status           # 查看状态"
echo ""
echo "  配置文件: /etc/nft-forward/rules.conf"
echo "  日志文件: /var/log/nft-forward.log"
echo ""
warn "提示: 请在防火墙(如 ufw/云服务商安全组)放行你设置的转发端口"
echo ""
