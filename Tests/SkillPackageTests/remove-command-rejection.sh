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
swift run --package-path "$项目目录" am-playlist remove --input "$临时目录/不存在.json" \
    --receipt-dir "$临时目录/收据" >"$标准输出" 2>"$标准错误"
退出码=$?
set -e

[[ "$退出码" -eq 2 ]]
[[ ! -s "$标准输出" ]]
grep -F "错误：实际删除必须同时提供 --approved 和 --receipt-token。" "$标准错误" >/dev/null
! grep -F "$临时目录" "$标准错误" >/dev/null
