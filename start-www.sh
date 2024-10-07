#!/bin/sh
# build latest commit
./dist.sh

cd "www" || exit

# download latest stable
wget -O "public/zoom-platform.sh" "https://github.com/ZOOM-Platform/zoom-platform.sh/releases/latest/download/zoom-platform.sh"

deno task start