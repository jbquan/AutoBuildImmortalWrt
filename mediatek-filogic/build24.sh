#!/bin/bash
source shell/custom-packages.sh

# =========================================================
# 1. 環境初始化
# =========================================================
echo "🛠️ 正在初始化編譯環境..."
echo "option check_signature 0" >> /etc/opkg.conf
date -s "2026-04-03 00:30:00"

# =========================================================
# 2. 同步倉庫與配置
# =========================================================
echo "🔄 正在同步第三方倉庫..."
if [ ! -d "/tmp/store-run-repo" ]; then
    git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo || { echo "❌ Git clone 失敗"; exit 1; }
fi

mkdir -p /home/build/immortalwrt/extra-packages
cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

sh shell/prepare-packages.sh

sed -i '1i\
arch aarch64_generic 10\n\
arch aarch64_cortex-a53 15' repositories.conf

# =========================================================
# 3. 內核優化植入
# =========================================================
echo "🚀 正在植入內核優化參數..."
mkdir -p /home/build/immortalwrt/files/etc
cat << EOF > /home/build/immortalwrt/files/etc/sysctl.conf
net.core.netdev_max_backlog=16384
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_fastopen=3
net.netfilter.nf_conntrack_max=65535
net.netfilter.nf_conntrack_tcp_timeout_established=7440
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

# =========================================================
# 4. 生成配置文件 (PPPoE)
# =========================================================
mkdir -p /home/build/immortalwrt/files/etc/config
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

# =========================================================
# 5. 定義安裝包清單
# =========================================================
PACKAGES=""

# [基礎與 UI]
PACKAGES="$PACKAGES curl luci luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn luci-i18n-dufs-zh-cn"

# [🎮 UPnP 支持 - PlayStation 聯機關鍵]
PACKAGES="$PACKAGES luci-app-upnp luci-i18n-upnp-zh-cn"

# [核心網絡與性能優化]
PACKAGES="$PACKAGES -dnsmasq dnsmasq-full"
PACKAGES="$PACKAGES kmod-nft-socket kmod-nft-tproxy kmod-nft-nat kmod-tun"
PACKAGES="$PACKAGES ip-full ipset iptables-nft kmod-tcp-bbr"
# CPU 多核負載均衡優化 (推薦 MT7981 使用)
PACKAGES="$PACKAGES irqbalance"

# [📱 USB 隨身 WiFi (F50) 與手機共享全家桶]
# 基礎 USB 及模式切換 (防止 F50 變成隨身碟)
PACKAGES="$PACKAGES kmod-usb-core kmod-usb2 kmod-usb3 usbutils usb-modeswitch"
# F50 / Android RNDIS 驅動
PACKAGES="$PACKAGES kmod-usb-net kmod-usb-net-rndis kmod-usb-net-cdc-ether"
# iPhone 分享驅動
PACKAGES="$PACKAGES kmod-usb-net-ipheth"
# 基礎 USB 儲存掛載 (方便第時插 USB 手指)
PACKAGES="$PACKAGES block-mount kmod-fs-ext4 kmod-fs-vfat"

# [🔥 PassWall 與 精準 SSR 核心]
PACKAGES="$PACKAGES ca-bundle ca-certificates libustream-openssl coreutils-base64 unzip"
PACKAGES="$PACKAGES chinadns-ng xray-core sing-box"
# 強制編譯時寫入 SSR 核心，解決訂閱為 0 問題
PACKAGES="$PACKAGES shadowsocksr-libev-ssr-local shadowsocksr-libev-ssr-redir shadowsocksr-libev-ssr-check"
PACKAGES="$PACKAGES luci-app-passwall luci-i18n-passwall-zh-cn"

# [網絡加速]
PACKAGES="$PACKAGES luci-app-turboacc luci-i18n-diskman-zh-cn"

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

# OpenClash 下載
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 配置 OpenClash..."
    mkdir -p files/etc/openclash/core
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget --no-check-certificate -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta || echo "⚠️ Clash Core 下載失敗"
    chmod +x files/etc/openclash/core/clash_meta
fi

# =========================================================
# 7. 開始構建
# =========================================================
echo "Building for profile: $PROFILE"
make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" V=s

if [ $? -ne 0 ]; then
    echo "❌ Error: Build failed!"
    exit 1
fi

echo "🎉 Build completed successfully."
