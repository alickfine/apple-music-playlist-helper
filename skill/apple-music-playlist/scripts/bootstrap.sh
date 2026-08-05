#!/bin/zsh
set -euo pipefail

技能根目录="${0:A:h:h}"
执行层目录="${技能根目录}/assets/helper"

[[ "$(uname -s)" == 'Darwin' ]] || { print -u2 '此技能的本机执行层仅支持 macOS。'; exit 2; }
command -v swift >/dev/null 2>&1 || {
  print -u2 '未找到 Swift。请先安装 Xcode Command Line Tools：xcode-select --install'
  exit 2
}
[[ -f "${执行层目录}/Package.swift" ]] || { print -u2 '技能执行层不完整：缺少 Package.swift。'; exit 2; }

swift build -c release --package-path "${执行层目录}" >&2
二进制目录=$(swift build -c release --show-bin-path --package-path "${执行层目录}")
二进制="${二进制目录}/am-playlist"
[[ -x "${二进制}" ]] || { print -u2 'Release 构建完成但未找到 am-playlist。'; exit 2; }

if [[ "${1:-}" == '--print-binary' ]]; then
  print -r -- "${二进制}"
else
  print "本机执行层已就绪：${二进制}"
fi
