#!/bin/zsh
set -euo pipefail

项目目录="${0:A:h:h}"
目标目录="${1:-${HOME}/.local/bin}"
可执行文件="${项目目录}/.build/release/am-playlist"

cd "${项目目录}"
swift build -c release
mkdir -p "${目标目录}"
install -m 755 "${可执行文件}" "${目标目录}/am-playlist"

print "已安装：${目标目录}/am-playlist"
