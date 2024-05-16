#!/bin/sh
set -e

cd "$(dirname "$0")"
FINAL_FILE="zoom-platform.sh"

# Download innoextract binaries
rm -f innoextract.tar.gz innoextract-upx.tar.gz
INNOEXT_URLS=$(curl -s "https://api.github.com/repos/doZennn/innoextract/releases/latest" | grep '"browser_download_url":.*innoextract.*.tar.gz' | sed -E 's/.*"([^"]+)".*/\1/')
echo "$INNOEXT_URLS" | wget -nv -i -

# Extract binaries
tar -xzf innoextract-upx.tar.gz

./build.sh "src.sh" "innoextract-upx" > "$FINAL_FILE"