#!/bin/sh
rm -rf out/
wget "https://github.com/ZOOM-Platform/zoom-platform.sh/releases/latest/download/zoom-platform.sh"
mv zoom-platform.sh out/
cp -r src/ out/
