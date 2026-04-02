#!/bin/bash
source shell/custom-packages.sh
# 该文件实际为imagebuilder容器内的build.sh

# =========================================================
# 1. 環境初始化：修復 SSL 同時間問題
# =========================================================
echo "🛠️ 正在初始化編譯環境..."
echo "option check_signature 0" >> /etc/opkg.conf
date -s "2026-04-02 23:55:00"

# =========================================================
# 2. 同步第三方倉庫與架構配置
# =========================================================
echo "🔄 正在同步第三方軟件倉庫..."
if [ ! -d "/tmp/store-run-repo" ]; then
    git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo || { echo "❌ Git clone 失敗"; exit 1; }
fi

mkdir -p /home/build/immortalwrt/extra-packages
cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

sh shell/prepare-packages.sh

# 修正：針對 MT7981B (Cortex-A53) 的架構優化
sed -i '1i\
arch aarch64_generic 10\n\
arch aarch64_cortex-a53 15' repositories.conf

# =========================================================
# 3. 內核優化植入 (提升網絡穩定性與轉發效能)
# =========================================================
echo "🏎️ 正在寫入內核優化參數..."
mkdir -p /home/build/immortalwrt/files/etc
cat << EOF >> /home/build/immortalwrt/files/etc/sysctl.conf
# 網絡併發優化
net.core.netdev_max_backlog=16384
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_fastopen=3
net.netfilter.nf_conntrack_max=65535
net.netfilter.nf_conntrack_tcp_timeout_established=7440
# 記憶體與 Swap 優化
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

# =========================================================
# 4. 生成 PPPoE 配置
# =========================================================
mkdir -p /home/build/immortalwrt/files/etc/config
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

# =========================================================
# 5. 定義安裝包清單 (重點：SSR 核心修復)
# =========================================================
PACKAGES=""

# [基礎 UI 與系統組件]
PACKAGES="$PACKAGES curl luci luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn luci-i18n-dufs-zh-cn"

# [🎮 UPnP 支持：解決 PlayStation NAT 問題]
PACKAGES="$PACKAGES luci-app-upnp luci-i18n-upnp-zh-cn"

# [核心依賴：解決 dnsmasq 衝突與 BBR]
PACKAGES="$PACKAGES -dnsmasq dnsmasq-full"
PACKAGES="$PACKAGES kmod-nft-socket kmod-nft-tproxy kmod-nft-nat kmod-tun"
PACKAGES="$PACKAGES ip-full ipset iptables-nft kmod-tcp-bbr"

# [🔥 PassWall 完整全家桶：包含所有 SSR 核心]
PACKAGES="$PACKAGES ca-bundle ca-certificates libustream-openssl coreutils-base64 unzip"
PACKAGES="$PACKAGES chinadns-ng xray-core sing-box"

# --- 重點：SSR 核心修復 (用 shadowsocksr-libev-alt 兼容性最強) ---
PACKAGES="$PACKAGES shadowsocksr-libev-alt shadowsocks-libev-ss-local shadowsocks-libev-ss-redir"
# -----------------------------------------------------------

PACKAGES="$PACKAGES luci-app-passwall luci-i18n-passwall-zh-cn"

# [網絡加速與磁盤管理]
# ⚠️ 注意：luci-app-turboacc 在 24.10 建議不帶 i18n 以防 Error 255
PACKAGES="$PACKAGES luci-app-turboacc"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"

# =========================================================
# 6. 動態邏輯處理
# =========================================================
if [ "$PROFILE" = "glinet_gl-axt1800" ] || [ "$PROFILE" = "glinet_gl-ax1800" ]; then
    PACKAGES="$PACKAGES -luci-i18n-diskman-zh-cn luci-i18n-homeproxy-zh-cn"
else
    PACKAGES="$PACKAGES $CUSTOM_PACKAGES"
fi

if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
fi

# OpenClash 處理
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 配置 OpenClash..."
    mkdir -p files/etc/openclash/core
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget --no-check-certificate -qO- $META_URL | tar xOvz > files
