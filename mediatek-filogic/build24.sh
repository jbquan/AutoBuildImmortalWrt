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
echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

# 拷贝 run/arm64 下所有 run 文件和ipk文件 到 extra-packages 目录
mkdir -p /home/build/immortalwrt/extra-packages
cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

echo "✅ Run files copied to extra-packages:"
ls -lh /home/build/immortalwrt/extra-packages/*.run

# 解压并拷贝ipk到packages目录
sh shell/prepare-packages.sh
ls -lah /home/build/immortalwrt/packages/

# 添加架构优先级信息 (MT7981B 为 Cortex-A53)
sed -i '1i\
arch aarch64_generic 10\n\
arch aarch64_cortex-a53 15' repositories.conf

# =========================================================
# 3. 配置文件生成 (PPPoE等)
# =========================================================
echo "Building for profile: $PROFILE"
echo "Include Docker: $INCLUDE_DOCKER"
echo "Create pppoe-settings"
mkdir -p /home/build/immortalwrt/files/etc/config

cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings:"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting build process..."

# =========================================================
# 4. 定义所需安装的包列表 (重点修补区域)
# =========================================================
PACKAGES=""

# [基础组件与 UI]
PACKAGES="$PACKAGES curl luci luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn luci-i18n-dufs-zh-cn"

# [核心修复：解决依赖冲突与透明代理警告]
PACKAGES="$PACKAGES -dnsmasq dnsmasq-full"
PACKAGES="$PACKAGES kmod-nft-socket kmod-nft-tproxy kmod-nft-nat kmod-tun"
PACKAGES="$PACKAGES ip-full ipset iptables-nft kmod-tcp-bbr"

# [🔥 PassWall 全家桶：解决无法订阅与无法运行]
# 1. 订阅必备 (HTTPS处理与Base64解码)
PACKAGES="$PACKAGES ca-bundle ca-certificates libustream-openssl coreutils-base64 unzip"
# 2. 核心组件 (DNS防污染与代理引擎)
PACKAGES="$PACKAGES chinadns-ng xray-core sing-box"
# 3. LuCI 界面
PACKAGES="$PACKAGES luci-app-passwall luci-i18n-passwall-zh-cn"

# [网络加速与磁盘管理]
PACKAGES="$PACKAGES luci-app-turboacc"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"

# =========================================================
# 5. 动态逻辑处理 (第三方包、Docker、OpenClash)
# =========================================================
# 合并自定义第三方包
if [ "$PROFILE" = "glinet_gl-axt1800" ] || [ "$PROFILE" = "glinet_gl-ax1800" ]; then
    echo "Model:$PROFILE not support third-parted packages"
    PACKAGES="$PACKAGES -luci-i18n-diskman-zh-cn luci-i18n-homeproxy-zh-cn"
else
    echo "Other Model:$PROFILE"
    PACKAGES="$PACKAGES $CUSTOM_PACKAGES"
fi

# Docker 支持判断
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# OpenClash 自动处理核心与数据库
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    # 添加 --no-check-certificate 确保下载成功
    wget --no-check-certificate -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    wget --no-check-certificate -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget --no-check-certificate -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

# =========================================================
# 6. 开始构建镜像
# =========================================================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

# 增加 V=s 开启详细日志输出，方便排错
make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" V=s

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ❌ Error: Build failed! 请检查上方日志中的 Unknown package 报错。"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - 🎉 Build completed successfully."
