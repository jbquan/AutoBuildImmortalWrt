#!/bin/bash
# =========================================================
# Cudy TR3000 (MT7981) 专用 ImageBuilder 编译脚本
# 修补版：解决 dnsmasq 冲突、内核模块缺失及 SSL 校验问题
# =========================================================

# 1. 环境初始化：解决系统时间不准导致的 SSL 报错
echo "🛠️ 正在初始化编译环境..."
date -s "2026-04-02 00:00:00"
echo "option check_signature 0" >> /etc/opkg.conf

# 2. 同步第三方软件仓库 (wukongdaily/store)
echo "🔄 正在同步第三方软件仓库..."
git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

# 拷贝并准备软件包
mkdir -p /home/build/immortalwrt/extra-packages
cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/
sh shell/prepare-packages.sh

# 添加架构优先级信息
sed -i '1i\arch aarch64_generic 10\narch aarch64_cortex-a53 15' repositories.conf

# 3. 核心软件包定义
PACKAGES=""

# --- [基础组件与界面] ---
PACKAGES="$PACKAGES curl luci luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn luci-i18n-dufs-zh-cn"

# --- [核心修复：解决 Error 255 & 透明代理失效] ---
# 必须显式剔除默认 dnsmasq 并安装 full 版，否则 PassWall 无法正常工作且编译会报错
PACKAGES="$PACKAGES -dnsmasq dnsmasq-full"
# 补全 nftables 透明代理必备内核模块（解决订阅后警告问题）
PACKAGES="$PACKAGES kmod-nft-socket kmod-nft-tproxy kmod-nft-nat kmod-tun"
# 补全底层网络工具与 BBR 加速
PACKAGES="$PACKAGES ip-full ipset iptables-nft kmod-tcp-bbr"

# --- [插件集成] ---
# PassWall (核心插件)
PACKAGES="$PACKAGES luci-app-passwall luci-i18n-passwall-zh-cn"

# 网络加速 (去掉了报错的 luci-i18n-turboacc-zh-cn，主插件通常自带中文或自动匹配)
PACKAGES="$PACKAGES luci-app-turboacc"

# 磁盘管理
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"

# 4. 第三方软件包与机型特殊逻辑
if [ "$PROFILE" = "glinet_gl-axt1800" ] || [ "$PROFILE" = "glinet_gl-ax1800" ]; then
    echo "⚠️ 机型 $PROFILE 处理逻辑..."
    PACKAGES="$PACKAGES -luci-i18n-diskman-zh-cn luci-i18n-homeproxy-zh-cn"
else
    # 这里合并 YML 传入的自定义包
    PACKAGES="$PACKAGES $CUSTOM_PACKAGES"
fi

# Docker 逻辑
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
fi

# 5. OpenClash 特殊处理 (如果 PACKAGES 中包含则下载内核)
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "🚀 正在为 OpenClash 注入内核与数据库..."
    mkdir -p files/etc/openclash/core
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    # 使用 --no-check-certificate 确保下载成功
    wget --no-check-certificate -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    wget --no-check-certificate -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget --no-check-certificate -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
fi

# 6. 配置 PPPOE 默认值 (保持原逻辑)
mkdir -p /home/build/immortalwrt/files/etc/config
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

# 7. 开始构建
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始为 $PROFILE 构建镜像..."
echo "选定包列表: $PACKAGES"

# 执行编译，使用 V=s 打印详细日志
make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" V=s

if [ $? -ne 0 ]; then
    echo "❌ 编译失败！请检查上方输出找到具体报错的软件包。"
    exit 1
fi

echo "🎉 编译成功！固件已生成在 bin/targets/ 目录下。"
