#!/bin/zsh
set -euo pipefail

仓库根目录="${0:A:h:h}"
源目录="${仓库根目录}/Sources/"
目标目录="${仓库根目录}/skill/apple-music-playlist/assets/helper/Sources/"

[[ -d "${源目录}" ]] || { print -u2 "找不到执行层源码：${源目录}"; exit 1; }
mkdir -p "${目标目录}"
rsync -a --delete "${源目录}" "${目标目录}"
print '技能执行层源码已同步。'
