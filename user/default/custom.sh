#!/bin/bash

set -e

echo "=============================================="
echo "Running custom commands"

# -------------------------------------------------
# Existing W1700K custom files
# -------------------------------------------------

mv files/overview.js \
    feeds/luci/applications/luci-app-attendedsysupgrade/htdocs/luci-static/resources/view/attendedsysupgrade/overview.js

mkdir -p feeds/luci/modules/luci-mod-status/patches

mv files/998-single-wiphy.patch \
    feeds/luci/modules/luci-mod-status/patches/998-single-wiphy.patch


# -------------------------------------------------
# Install latest Aurora LuCI theme
# -------------------------------------------------

echo "Installing latest Aurora LuCI theme..."

rm -rf package/luci-theme-aurora

if ! git clone \
    --depth=1 \
    https://github.com/eamonxg/luci-theme-aurora.git \
    package/luci-theme-aurora
then
    echo "ERROR: Failed to download Aurora theme!"
    exit 1
fi

if [ ! -f package/luci-theme-aurora/Makefile ]; then
    echo "ERROR: Aurora theme was downloaded, but Makefile is missing!"
    exit 1
fi

echo "Aurora theme installed successfully."


# -------------------------------------------------
# Install Aurora theme configuration app
# -------------------------------------------------

echo "Installing Aurora theme configuration app..."

rm -rf package/luci-app-aurora-config

if ! git clone \
    --depth=1 \
    https://github.com/eamonxg/luci-app-aurora-config.git \
    package/luci-app-aurora-config
then
    echo "ERROR: Failed to download Aurora theme configuration app!"
    exit 1
fi

if [ ! -f package/luci-app-aurora-config/Makefile ]; then
    echo "ERROR: Aurora theme configuration app was downloaded, but Makefile is missing!"
    exit 1
fi

echo "Aurora theme configuration app installed successfully."

# -------------------------------------------------
# Install MosDNS (mosdns core + v2dat + luci-app-mosdns)
# -------------------------------------------------
echo "Installing latest MosDNS..."
rm -rf package/mosdns
if ! git clone --depth=1 https://github.com/sbwml/luci-app-mosdns.git package/mosdns; then
    echo "ERROR: Failed to download MosDNS!"; exit 1
fi
for pkg in mosdns v2dat luci-app-mosdns; do
    [ -f "package/mosdns/$pkg/Makefile" ] || { echo "ERROR: MosDNS component '$pkg' missing Makefile!"; exit 1; }
done
echo "MosDNS installed successfully."

# -------------------------------------------------
# Install latest OpenClash
# -------------------------------------------------
echo "Installing latest OpenClash..."
rm -rf /tmp/openclash-src package/luci-app-openclash
if ! git clone --depth=1 https://github.com/vernesong/OpenClash.git /tmp/openclash-src; then
    echo "ERROR: Failed to download OpenClash!"; exit 1
fi
mv /tmp/openclash-src/luci-app-openclash package/luci-app-openclash
rm -rf /tmp/openclash-src
[ -f package/luci-app-openclash/Makefile ] || { echo "ERROR: OpenClash missing Makefile!"; exit 1; }
echo "OpenClash installed successfully."

# -------------------------------------------------
# Enable Chinese language
# -------------------------------------------------

echo "Enabling Chinese language..."

grep -qxF 'CONFIG_LUCI_LANG_zh_Hans=y' .config || \
    echo 'CONFIG_LUCI_LANG_zh_Hans=y' >> .config

# -------------------------------------------------
# Install Turbo ACC (mufeng05 fork)
# (The device's own hardware acceleration -- e.g. HNAT -- already
#  handles flow acceleration, so turboacc's own "fastpath" engine
#  is shipped disabled by default -- see the config override below)
# -------------------------------------------------
echo "Installing Turbo ACC (mufeng05/turboacc)..."

# Remove any stale checkout to avoid the script's interactive overwrite prompt
rm -rf package/turboacc

if ! curl -sSL https://raw.githubusercontent.com/mufeng05/turboacc/main/add_turboacc.sh -o /tmp/add_turboacc.sh; then
    echo "ERROR: Failed to download add_turboacc.sh!"; exit 1
fi

if ! bash /tmp/add_turboacc.sh; then
    echo "ERROR: Failed to install Turbo ACC (mufeng05)!"; exit 1
fi
rm -f /tmp/add_turboacc.sh

# -------------------------------------------------
# Fix: mufeng05/turboacc's add_turboacc.sh has no
# "--no-sfe" switch (unlike other turboacc forks) --
# it unconditionally drops shortcut-fe/fast-classifier
# into package/turboacc/shortcut-fe. Combined with this
# config's CONFIG_ALL_KMODS=y, that pulls
# kmod-fast-classifier into the build by default, and it
# fails to compile against this device's Airoha AN7581
# kernel tree ("package/turboacc/shortcut-fe/shortcut-fe
# failed to build").
# We don't need it anyway -- the Airoha NPU already does
# hardware flow offload, and we only want nft-fullcone --
# so just remove the package before it can be built.
# -------------------------------------------------
echo "Removing turboacc's shortcut-fe (not needed, incompatible with this kernel tree)..."
rm -rf package/turboacc/shortcut-fe

[ -f package/turboacc/luci-app-turboacc/Makefile ] || { echo "ERROR: luci-app-turboacc missing Makefile!"; exit 1; }
[ -d package/turboacc/fullconenat-nft ] || { echo "ERROR: fullconenat-nft (nftables fullcone) package not installed!"; exit 1; }
[ -d package/turboacc/fullconenat ] || { echo "ERROR: fullconenat (iptables fullcone) package not installed!"; exit 1; }

if ! ls target/linux/generic/hack-*/952-add-net-conntrack-events-support-multiple-registrant.patch >/dev/null 2>&1; then
    echo "ERROR: 952 kernel patch not placed -- unsupported kernel version!"; exit 1
fi
echo "Turbo ACC (mufeng05) installed successfully."

# -------------------------------------------------
# Fix: the mufeng05/turboacc libnftnl patch adds a
# new source file via Makefile.am but ships no
# PKG_FIXUP, so OpenWrt tries to build from the
# stale (un-regenerated) configure/Makefile.in and
# fails with "package/libs/libnftnl failed to build".
# Force autoreconf so the patched Makefile.am
# actually takes effect.
# -------------------------------------------------
libnftnl_makefile="package/libs/libnftnl/Makefile"
if [ ! -f "$libnftnl_makefile" ]; then
    echo "ERROR: $libnftnl_makefile not found!"; exit 1
fi
if ! grep -q '^PKG_FIXUP:=autoreconf' "$libnftnl_makefile"; then
    sed -i '/^include \$(INCLUDE_DIR)\/package\.mk/i PKG_FIXUP:=autoreconf' "$libnftnl_makefile"
fi
grep -q '^PKG_FIXUP:=autoreconf' "$libnftnl_makefile" || { echo "ERROR: failed to inject PKG_FIXUP:=autoreconf into libnftnl Makefile!"; exit 1; }
echo "libnftnl PKG_FIXUP:=autoreconf applied."

# -------------------------------------------------
# Ship Turbo ACC with its acceleration ("fastpath")
# engine disabled by default
# -------------------------------------------------
# mufeng05/turboacc consolidates all acceleration engines (native
# Flow Offloading, MediaTek/Airoha HNAT, Shortcut-FE, QCA-NSS-ECM...)
# behind a single "fastpath" option. On first boot, its uci-defaults
# script auto-detects available kernel modules and enables one of
# them -- which is exactly what fights with this device's own
# hardware acceleration and forces a manual restart after every boot.
#
# We pre-seed /etc/config/turboacc with "global.set=1" so that the
# on-device uci-defaults script sees the config as already
# initialized and skips its auto-detection entirely, shipping with
# fastpath="none" (the flow-offload/HNAT engine is OFF). Full-cone
# NAT support (the reason turboacc was added in the first place)
# stays enabled. Users can still turn fastpath on manually from
# LuCI > Network > Turbo ACC if they ever want to test it.
turboacc_default_config="package/turboacc/luci-app-turboacc/root/etc/config/turboacc"
if [ ! -f "$turboacc_default_config" ]; then
    echo "ERROR: default turboacc config not found at $turboacc_default_config!"; exit 1
fi

cat > "$turboacc_default_config" <<-'EOF'
config turboacc 'global'
	option set '1'

config turboacc 'config'
	option fastpath 'none'
	option fullcone '1'
	option tcpcca 'cubic'
EOF

echo "Turbo ACC fastpath (flow-offload/HNAT engine) set to disabled by default."

# -------------------------------------------------
# Enable Turbo ACC (nft-fullcone)
# -------------------------------------------------

echo "Enabling Turbo ACC..."

grep -qxF 'CONFIG_PACKAGE_luci-app-turboacc=y' .config || \
    echo 'CONFIG_PACKAGE_luci-app-turboacc=y' >> .config
    
# -------------------------------------------------
# Enable Aurora
# -------------------------------------------------

echo "Enabling Aurora theme..."

grep -qxF 'CONFIG_PACKAGE_luci-theme-aurora=y' .config || \
    echo 'CONFIG_PACKAGE_luci-theme-aurora=y' >> .config

grep -qxF 'CONFIG_PACKAGE_luci-app-aurora-config=y' .config || \
    echo 'CONFIG_PACKAGE_luci-app-aurora-config=y' >> .config


# -------------------------------------------------
# Clean LuCI temporary files
# -------------------------------------------------

rm -rf /tmp/luci-*


echo "=============================================="
echo "Custom commands completed"
