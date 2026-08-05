#!/bin/zsh
set -euo pipefail

技能根目录="${0:A:h:h}"

[[ "${1:-}" == 'add' ]] || {
  print -u2 '此技能执行层仅支持 add；删除、移动、重排、分享和下载不在能力范围内。'
  exit 2
}

二进制=$(zsh "${技能根目录}/scripts/bootstrap.sh" --print-binary)
[[ -x "${二进制}" ]] || { print -u2 '本机执行层不可执行。'; exit 2; }
exec "${二进制}" "$@"
