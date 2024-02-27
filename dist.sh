#!/bin/sh

set -e

FINAL_FILE="zoom-platform.sh"

cp "src.sh" "$FINAL_FILE"

# Add licences to header
HASHEDLIC=$(sed 's/^/# /' < LICENSE)
INNOLIC='###
# This script uses a fork of "innoextract" licensed under the zlib/libpng license.
#
# Original innoextract (c) Daniel Scharrer <daniel@constexpr.org> https://constexpr.org/innoextract/
# 
# Fork by Jozen Blue Martinez for ZOOM Platform https://github.com/doZennn/innoextract
###'

awk -i inplace -v r="###\n$HASHEDLIC\n###\n\n$INNOLIC" '{gsub(/#__LICENSE_HERE__/,r)}1' "$FINAL_FILE"

# set version to either release tag or commit hash
VERSION=$(git tag --points-at HEAD)
if [ -z "$VERSION" ]; then VERSION="git-$(git rev-parse --short HEAD)"; fi
sed -i "s/INSTALLER_VERSION=\"DEV\"/INSTALLER_VERSION=\"$VERSION\"/" "$FINAL_FILE"

# Download innoextract binaries
INNOEXT_URLS=$(curl -s "https://api.github.com/repos/doZennn/innoextract/releases/latest" | grep '"browser_download_url":.*innoextract.*.tar.gz' | sed -E 's/.*"([^"]+)".*/\1/')
echo "$INNOEXT_URLS" | wget -nv -i -

# Extract binaries
tar -xzf innoextract-upx.tar.gz

# Add innoextract binary to end
printf '__INNOEXTRACT_BINARY__\n' >> "$FINAL_FILE"
base64 -w 0 innoextract-upx >> "$FINAL_FILE"

chmod +x "$FINAL_FILE"