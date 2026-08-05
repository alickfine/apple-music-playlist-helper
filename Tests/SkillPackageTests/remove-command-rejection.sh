#!/bin/zsh
set -euo pipefail

项目目录="${0:A:h:h:h}"
临时目录="$(mktemp -d)"
清理() {
    退出状态=$?
    rm -rf -- "$临时目录"
    exit "$退出状态"
}
trap 清理 EXIT

标准输出="$临时目录/stdout"
标准错误="$临时目录/stderr"

set +e
swift run --package-path "$项目目录" am-playlist remove --input "$临时目录/不存在.json" >"$标准输出" 2>"$标准错误"
退出码=$?
set -e

[[ "$退出码" -eq 2 ]]
[[ ! -s "$标准输出" ]]
grep -F "错误：remove 命令暂未实现，已安全拒绝执行。" "$标准错误" >/dev/null
