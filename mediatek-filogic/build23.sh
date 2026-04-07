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
if [ -n "$CUSTOM_PACKAGES" ]; then
  echo "✅ 你选择了第三方软件包：$CUSTOM_PACKAGES"
  if [ "$PROFILE" = "glinet_gl-mt3000" ]; then
    echo "❌ 检查到您集成了第三方软件包 由于mt3000闪存空间较小 不支持此操作"
    echo "✅ 系统将自动帮你注释掉shell/custom-packages.sh中的插件 目前支持第三方插件集成的机型是mt2500/mt6000等大闪存机型"
    CUSTOM_PACKAGES=""
  else
    # 下载 run 文件仓库
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
    
    # 添加架构优先级信息 (RAX3000M 同样是 MT7981 Cortex-A53)
    sed -i '1i\
arch aarch64_generic 10\n\
arch aarch64_cortex-a53 15' repositories.conf
  fi
else
  echo "⚪️ 未选择任何第三方软件包"
fi

# =========================================================
# 3. 配置文件生成 (PPPoE等)
# =========================================================
echo "Building for profile: $PROFILE"
echo "Include Docker: $INCLUDE_DOCKER"
echo "Create pppoe-settings"
mkdir -p  /home/build/immortalwrt/files/etc/config

# 创建pppoe配置文件 yml传入pppoe变量————>pppoe-settings文件
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting build process..."

# =========================================================
# 4. 定义所需安装的包列表 (已集成核心修复、依赖与游戏优化)
# =========================================================
PACKAGES=""

# [基础组件与 UI]
PACKAGES="$PACKAGES curl luci luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn openssh-sftp-server"
# 注意：23.05 版本使用 opkg 替代了 24.10 的 package-manager
PACKAGES="$PACKAGES luci-i18n-opkg-zh-cn"

# [核心修复：解决 Error 255 依赖冲突与 nftables 警告]
PACKAGES="$PACKAGES -dnsmasq dnsmasq-full"
PACKAGES="$PACKAGES kmod-nft-socket kmod-nft-tproxy kmod-nft-nat kmod-tun"
PACKAGES="$PACKAGES ip-full ipset iptables-nft kmod-tcp-bbr"

# [文件管理与存储 (包含你需要的 iStore 环境基础组件)]
PACKAGES="$PACKAGES luci-i18n-filebrowser-zh-cn luci-i18n-samba4-zh-cn luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES fdisk script-utils"

# [🔥 代理全家桶与依赖 (支持 PassWall, OpenClash, HomeProxy 稳健运行)]
# 订阅与内核依赖
PACKAGES="$PACKAGES ca-bundle ca-certificates libustream-openssl coreutils-base64 unzip chinadns-ng xray-core sing-box"
# 插件本体
PACKAGES="$PACKAGES luci-app-passwall luci-i18n-passwall-zh-cn"
PACKAGES="$PACKAGES luci-app-openclash"
PACKAGES="$PACKAGES luci-app-homeproxy luci-i18n-homeproxy-zh-cn"

# [🚀 游戏与网络优化]
# 已添加 UPnP 与 TurboACC 
PACKAGES="$PACKAGES luci-app-upnp luci-i18n-upnp-zh-cn"
PACKAGES="$PACKAGES luci-app-turboacc"

# =========================================================
# 5. 动态逻辑处理 (第三方包、Docker、OpenClash)
# =========================================================
# 合并自定义第三方包
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ 已选择 luci-app-openclash，添加 openclash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    # 加入 --no-check-certificate 防止 SSL 报错中断编译
    wget --no-check-certificate -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
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

# 包含 V=s 启用详细日志，若报错可快速定位缺少的 ipk
make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" V=s

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ❌ Error: Build failed! 请查看上方详细日志中的 Unknown package 提示。"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - 🎉 Build completed successfully."
