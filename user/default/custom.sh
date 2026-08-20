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
# Install Turbo ACC (nft-fullcone), skip SFE
# (Airoha NPU hardware offload already handles flow acceleration)
# -------------------------------------------------
echo "Installing Turbo ACC (nft-fullcone, --no-sfe)..."

# Remove any stale checkout to avoid the script's interactive overwrite prompt
rm -rf package/turboacc

if ! curl -sSL https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh -o /tmp/add_turboacc.sh; then
    echo "ERROR: Failed to download add_turboacc.sh!"; exit 1
fi

if ! bash /tmp/add_turboacc.sh --no-sfe; then
    echo "ERROR: Failed to install Turbo ACC (nft-fullcone)!"; exit 1
fi
rm -f /tmp/add_turboacc.sh

[ -f package/turboacc/luci-app-turboacc/Makefile ] || { echo "ERROR: luci-app-turboacc missing Makefile!"; exit 1; }
[ -d package/turboacc/nft-fullcone ] || { echo "ERROR: nft-fullcone package not installed!"; exit 1; }

if ! ls target/linux/generic/hack-*/952-add-net-conntrack-events-support-multiple-registrant.patch >/dev/null 2>&1; then
    echo "ERROR: 952 kernel patch not placed -- unsupported kernel version!"; exit 1
fi
# Sanity check: --no-sfe must NOT bring in the SFE-only kernel patches
if ls target/linux/generic/hack-*/953-net-patch-linux-kernel-to-support-shortcut-fe.patch >/dev/null 2>&1; then
    echo "ERROR: SFE patch 953 present even though --no-sfe was requested!"; exit 1
fi
echo "Turbo ACC (nft-fullcone) installed successfully."

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
