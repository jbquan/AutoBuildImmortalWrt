#!/bin/bash
# 导入自定义包变量 (如果 shell/custom-packages.sh 中有定义)
[ -f shell/custom-packages.sh ] && source shell/custom-packages.sh

# 1. 基础环境修复：忽略 SSL 证书错误（解决你之前的 wget/opkg 报错）
echo "option check_signature 0" >> /etc/opkg.conf
# 尝试同步一个大概的时间，防止证书尚未生效
date -s "2026-04-02 00:00:00"

# 2. 同步第三方软件仓库
echo "🔄 正在同步第三方软件仓库..."
git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

# 拷贝并准备软件包
mkdir -p /home/build/immortalwrt/extra-packages
cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/
sh shell/prepare-packages.sh

# 添加架构优先级
sed -i '1i\arch aarch64_generic 10\narch aarch64_cortex-a53 15' repositories.conf

# 3. 定义插件列表
PACKAGES=""

# --- 基础组件 ---
PACKAGES="$PACKAGES curl luci luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon luci-app-argon-config luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn luci-i18n-ttyd-zh-cn openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn luci-i18n-dufs-zh-cn"

# --- 核心修补：解决 Error 255 冲突与依赖 ---
# 必须先卸载标准版 dnsmasq，再安装 dnsmasq-full，否则编译必报错
PACKAGES="$PACKAGES -dnsmasq dnsmasq-full"
# 补全 PassWall 订阅后报错缺失的内核模块
PACKAGES="$PACKAGES kmod-nft-socket kmod-nft-tproxy kmod-nft-nat kmod-tun"
# 补全底层网络工具
PACKAGES="$PACKAGES ip-full ipset iptables-nft"

# --- 核心插件 ---
# PassWall
PACKAGES="$PACKAGES luci-app-passwall luci-i18n-passwall-zh-cn"
# 网络加速 (TR3000 必装)
PACKAGES="$PACKAGES luci-app-turboacc luci-i18n-turboacc-zh-cn"
# 磁盘管理
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"

# 4. 第三方软件包与机型逻辑
if [ "$PROFILE" = "glinet_gl-axt1800" ] || [ "$PROFILE" = "glinet_gl-ax1800" ]; then
    echo "⚠️ 机型 $PROFILE 暂不支持部分第三方插件"
    PACKAGES="$PACKAGES -luci-i18n-diskman-zh-cn luci-i18n-homeproxy-zh-cn"
else
    echo "✅ 标准机型编译: $PROFILE"
    PACKAGES="$PACKAGES $CUSTOM_PACKAGES"
fi

# Docker 支持
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
fi

# 5. OpenClash 特殊处理 (保持原逻辑并增强)
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "🚀 检测到 OpenClash，注入内核与数据库..."
    mkdir -p files/etc/openclash/core
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    # 使用 --no-check-certificate 彻底解决 SSL 校验问题
    wget --no-check-certificate -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    wget --no-check-certificate -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget --no-check-certificate -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
fi

# 6. 执行构建
echo "🛠️ 开始构建镜像..."
echo "选定的软件包: $PACKAGES"

# 增加 V=s 参数以便在 GitHub Actions 日志中看到具体的报错包名
make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" V=s

if [ $? -ne 0 ]; then
    echo "❌ 编译失败，请检查上方 V=s 输出的详细错误日志"
    exit 1
fi

echo "🎉 编译成功完成！"
