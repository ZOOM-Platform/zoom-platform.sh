#!/bin/sh
set -e

cd "$(dirname "$0")"

INPUT=$1
INNOBIN=$2

SCRIPT=$(cat "$INPUT")

# Add licences to header
HASHEDLIC=$(sed 's/^/# /' < LICENSE)
INNOLIC='###
# This script uses a fork of "innoextract" licensed under the zlib/libpng license.
#
# Original innoextract (c) Daniel Scharrer <daniel@constexpr.org> https://constexpr.org/innoextract/
# Fork by Jozen Blue Martinez for ZOOM Platform https://github.com/doZennn/innoextract
###'
SCRIPT=$(printf "%s" "$SCRIPT" | awk -v r="###\n$HASHEDLIC\n###\n\n$INNOLIC" '{gsub(/#__LICENSE_HERE__/,r)}1')

# set version to either release tag or commit hash
VERSION=$(git tag --points-at HEAD)
[ -z "$VERSION" ] && VERSION="git-$(git rev-parse --short=7 HEAD)"
SCRIPT=$(printf "%s" "$SCRIPT" | sed "s/INSTALLER_VERSION=\"DEV\"/INSTALLER_VERSION=\"$VERSION\"/")

# Add innoextract binary between comments
START=$(printf "%s" "$SCRIPT" | sed -n '1,/^#__INNOEXTRACT_BINARY_START__/p')
# shellcheck disable=SC2016
END=$(printf "%s" "$SCRIPT" | sed -n '/^#__INNOEXTRACT_BINARY_END__$/,${p;}')
INNOB64=$(base64 -w 0 "$INNOBIN")
printf '%s\nINNOEXTRACT_BINARY_B64=%s\n%s' "$START" "$INNOB64" "$END"
