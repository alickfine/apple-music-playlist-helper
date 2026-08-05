#!/bin/zsh
set -euo pipefail

技能根目录="${0:A:h:h}"

case "${1:-}" in
  add|remove) ;;
  *)
    print -u2 '此技能执行层仅支持 add 和 remove；移动、重排、分享、下载及资料库文件删除均被拒绝。'
    exit 2
    ;;
esac

二进制=$(zsh "${技能根目录}/scripts/bootstrap.sh" --print-binary)
[[ -x "${二进制}" ]] || { print -u2 '本机执行层不可执行。'; exit 2; }
exec "${二进制}" "$@"
