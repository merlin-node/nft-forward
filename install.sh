#!/bin/bash
# nft-forward 安装脚本
# 用法(任选其一):
#   bash <(curl -fsSL https://raw.githubusercontent.com/merlin-node/nft-forward/main/install.sh)
#   bash <(wget -qO- https://raw.githubusercontent.com/merlin-node/nft-forward/main/install.sh)
#   本地: sudo bash install.sh   (同目录有 nft-forward 时直接用本地文件)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

msg()  { echo -e "${GREEN}[*]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*"; }

RAW_BASE="https://raw.githubusercontent.com/merlin-node/nft-forward/main"
GH_MIRRORS=("" "https://ghproxy.net/" "https://gh-proxy.com/")
IS_UPDATE="${NFT_FORWARD_UPDATE:-0}"

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

http_get() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 120 "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- -T 15 -t 2 "$1"
    else
        return 1
    fi
}

# 下载仓库文件:直连失败自动走镜像,校验是完整的 bash 脚本
fetch_repo_file() {
    local name="$1" dest="$2" m
    for m in "${GH_MIRRORS[@]}"; do
        if http_get "${m}${RAW_BASE}/${name}" > "$dest" 2>/dev/null \
            && head -1 "$dest" | grep -q '^#!/bin/bash' \
            && bash -n "$dest" 2>/dev/null; then
            [[ -n "$m" ]] && warn "GitHub 直连失败,已通过镜像下载: $m"
            return 0
        fi
    done
    return 1
}

if [[ $EUID -ne 0 ]]; then
    err "需要 root 权限,请用 sudo 运行"
    exit 1
fi

# 检查系统(更新时不再问)
if [[ "$IS_UPDATE" != "1" ]] && ! grep -qi debian /etc/os-release 2>/dev/null; then
    warn "本脚本针对 Debian 设计,其他系统可能有兼容问题"
    read -rp "继续? [y/N]: " yn
    [[ "$yn" =~ ^[Yy]$ ]] || exit 0
fi

# 本地有 nft-forward 就用本地的;通过 bash <(curl ...) 运行时 $0 是 /dev/fd/xx,自动在线下载
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo /nonexistent)"
TMPDIR_INSTALL=$(mktemp -d)
trap 'rm -rf "$TMPDIR_INSTALL"' EXIT

msg "1/6 检查依赖..."
need_pkgs=()
command -v nft  >/dev/null 2>&1 || need_pkgs+=(nftables)
command -v ss   >/dev/null 2>&1 || need_pkgs+=(iproute2)
command -v curl >/dev/null 2>&1 || need_pkgs+=(curl ca-certificates)
command -v tar  >/dev/null 2>&1 || need_pkgs+=(tar)
if (( ${#need_pkgs[@]} > 0 )); then
    msg "    安装: ${need_pkgs[*]}"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${need_pkgs[@]}" >/dev/null
else
    msg "    依赖已齐全,跳过 apt"
fi

msg "2/6 安装主程序到 /usr/local/bin/nft-forward..."
if [[ -f "$SCRIPT_DIR/nft-forward" ]]; then
    SRC="$SCRIPT_DIR/nft-forward"
else
    SRC="$TMPDIR_INSTALL/nft-forward"
    if ! fetch_repo_file nft-forward "$SRC"; then
        err "下载 nft-forward 失败,请检查网络"
        exit 1
    fi
fi
bash -n "$SRC" || { err "nft-forward 语法检查失败,已中止"; exit 1; }
install -m 755 "$SRC" /usr/local/bin/nft-forward

# 创建短命令 zf
ln -sf /usr/local/bin/nft-forward /usr/local/bin/zf

msg "3/6 创建配置目录..."
mkdir -p /etc/nft-forward
chmod 700 /etc/nft-forward

# 更新时保留用户设置的 DDNS 间隔
DDNS_MIN=5
if [[ -f /etc/nft-forward/settings.conf ]]; then
    v=$(grep -oP '^DDNS_INTERVAL_MIN=\K[0-9]+' /etc/nft-forward/settings.conf || true)
    [[ -n "$v" ]] && DDNS_MIN="$v"
fi

msg "4/6 安装 systemd 服务..."

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
cat > /etc/systemd/system/nft-forward-ddns.timer <<EOF
[Unit]
Description=nft-forward DDNS update timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=${DDNS_MIN}min
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
systemctl restart nft-forward-ddns.timer

# 启用 nftables.service(系统默认的持久化方式,但我们用独立 table 不冲突)
systemctl enable nftables.service >/dev/null 2>&1 || true

# 更新后按新版本重新生成并应用规则(nft 和 realm)
if [[ -f /etc/nft-forward/rules.conf ]]; then
    /usr/local/bin/nft-forward apply || warn "规则重新应用时有报错,进菜单查看"
fi

if [[ "$IS_UPDATE" == "1" ]]; then
    msg "更新完成"
    exit 0
fi

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
echo "    zf realm-install    # 安装/更新 realm(添加 realm 规则时也会提示安装)"
echo ""
echo "  配置文件: /etc/nft-forward/rules.conf"
echo "  日志文件: /var/log/nft-forward.log"
echo ""
warn "提示: 请在防火墙(如 ufw/云服务商安全组)放行你设置的转发端口"
echo ""
