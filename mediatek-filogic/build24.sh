#!/bin/bash
source shell/custom-packages.sh
# 该文件实际为imagebuilder容器内的build.sh

# =========================================================
# 1. 环境初始化：修复系统时间与 SSL 校验问题
# =========================================================
echo "🛠️ 正在初始化编译环境并修复 SSL 校验..."
echo "option check_signature 0" >> /etc/opkg.conf
date -s "2026-04-02 00:00:00"

# =========================================================
# 2. 同步第三方软件仓库与配置架构
# =========================================================
echo "🔄 正在同步第三方软件仓库..."
# 优化建议：加入下载判断，避免重复下载失败
if [ ! -d "/tmp/store-run-repo" ]; then
    git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo || { echo "❌ Git clone 失败"; exit 1; }
fi

mkdir -p /home/build/immortalwrt/extra-packages
cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

sh shell/prepare-packages.sh

# 添加架构优先级信息 (MT7981B)
sed -i '1i\
arch aarch64_generic 10\n\
arch aarch64_cortex-a53 15' repositories.conf

# =========================================================
# 3. 內核優化與系統參數 (New: Kernel Optimization)
# =========================================================
echo "🚀 正在植入內核優化參數..."
mkdir -p /home/build/immortalwrt/files/etc
cat << EOF >> /home/build/immortalwrt/files/etc/sysctl.conf
# 提升網絡併發處理能力
net.core.netdev_max_backlog=16384
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_fastopen=3
# 優化記憶體回收與快取
vm.swappiness=10
vm.vfs_cache_pressure=50
# 轉發加速優化
net.netfilter.nf_conntrack_max=65535
net.netfilter.nf_conntrack_tcp_timeout_established=7440
EOF

# =========================================================
# 4. 配置文件生成
# =========================================================
mkdir -p /home/build/immortalwrt/files/etc/config
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

# =========================================================
# 5. 定义所需安装的包列表
# =========================================================
PACKAGES=""

# [基础组件与 UI]
PACKAGES="$PACKAGES curl luci luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn luci-i18n-dufs-zh-cn"

# [🔥 UPnP 支持：解決遊戲 NAT 類型問題]
PACKAGES="$PACKAGES luci-app-upnp luci-i18n-upnp-zh-cn"

# [核心修复：解決依賴衝突]
PACKAGES="$PACKAGES -dnsmasq dnsmasq-full"
PACKAGES="$PACKAGES kmod-nft-socket kmod-nft-tproxy kmod-nft-nat kmod-tun"
PACKAGES="$PACKAGES ip-full ipset iptables-nft kmod-tcp-bbr"

# [PassWall 穩定運行必備]
PACKAGES="$PACKAGES ca-bundle ca-certificates libustream-openssl coreutils-base64 unzip"
PACKAGES="$PACKAGES chinadns-ng xray-core sing-box"
PACKAGES="$PACKAGES luci-app-passwall luci-i18n-passwall-zh-cn"

# [网络加速]
PACKAGES="$PACKAGES luci-app-turboacc"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"

# =========================================================
# 6. 动态逻辑处理
# =========================================================
if [ "$PROFILE" = "glinet_gl-axt1800" ] || [ "$PROFILE" = "glinet_gl-ax1800" ]; then
    PACKAGES="$PACKAGES -luci-i18n-diskman-zh-cn luci-i18n-homeproxy-zh-cn"
else
    PACKAGES="$PACKAGES $CUSTOM_PACKAGES"
fi

if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
fi

# OpenClash 處理 (加入錯誤檢查與 HTTPS 忽略)
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 配置 OpenClash..."
    mkdir -p files/etc/openclash/core
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget --no-check-certificate -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta || echo "⚠️ Clash Core 下载失败"
    chmod +x files/etc/openclash/core/clash_meta
fi

# =========================================================
# 7. 开始构建镜像
# =========================================================
echo "Building for profile: $PROFILE"
make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" V=s

if [ $? -ne 0 ]; then
    echo "❌ Error: Build failed!"
    exit 1
fi

echo "🎉 Build completed successfully."
