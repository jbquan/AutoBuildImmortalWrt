# =========================================================
# 定义所需安装的包列表 (已集成 PassWall 与网络加速)
# =========================================================
PACKAGES=""

# 1. 基础组件与中文界面
PACKAGES="$PACKAGES curl luci luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"

# 2. 系统工具与文件管理
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn luci-i18n-dufs-zh-cn"

# 3. 核心插件：PassWall (你要求的)
# 注意：PassWall 通常依赖 chinadns-ng, sing-box 等，ImageBuilder 会自动尝试从 local packages 找依赖
PACKAGES="$PACKAGES luci-app-passwall luci-i18n-passwall-zh-cn"

# 4. 核心插件：网络加速 (Cudy TR3000 MTK 平台强烈建议)
PACKAGES="$PACKAGES luci-app-turboacc luci-i18n-turboacc-zh-cn"

# 5. 存储管理 (可选，TR3000 无 USB，仅建议用于分区查看)
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"

# =========================================================
# 第三方软件包 合并逻辑
# =========================================================
if [ "$PROFILE" = "glinet_gl-axt1800" ] || [ "$PROFILE" = "glinet_gl-ax1800" ]; then
    echo "Model:$PROFILE not support third-parted packages"
    PACKAGES="$PACKAGES -luci-i18n-diskman-zh-cn luci-i18n-homeproxy-zh-cn"
else
    echo "Current Model: $PROFILE - Standard Build"
    PACKAGES="$PACKAGES $CUSTOM_PACKAGES"
fi

# 判断是否需要编译 Docker 插件 (注意 TR3000 内存只有 512MB，跑 Docker 需谨慎)
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "✅ Adding package: luci-i18n-dockerman-zh-cn"
fi

# 6. OpenClash 自动处理逻辑 (保持你原有的逻辑)
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，正在准备内核..."
    mkdir -p files/etc/openclash/core
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
else
    echo "⚪️ 未选择 luci-app-openclash"
fi

# =========================================================
# 开始构建
# =========================================================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image for $PROFILE"
make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files"
