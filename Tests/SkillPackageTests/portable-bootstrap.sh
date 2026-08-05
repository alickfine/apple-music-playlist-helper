#!/bin/zsh
set -euo pipefail

仓库根目录="${0:A:h:h:h}"
临时根目录=$(mktemp -d)
trap 'rm -rf -- "${临时根目录}"' EXIT

安装根目录="${临时根目录}/skills"
zsh "${仓库根目录}/scripts/install-skill-local.sh" "${安装根目录}"
复制技能="${安装根目录}/apple-music-playlist"

[[ -f "${复制技能}/SKILL.md" ]] || { print -u2 '安装副本缺少 SKILL.md'; exit 1; }
[[ ! -e "${复制技能}/.git" ]] || { print -u2 '安装副本不应包含 Git 元数据'; exit 1; }
[[ ! -e "${复制技能}/assets/helper/.build" ]] || { print -u2 '安装初始包不应包含预编译产物'; exit 1; }

输出=$(zsh "${复制技能}/scripts/bootstrap.sh" --print-binary)
规范技能="${复制技能:A}"
规范输出="${输出:A}"
[[ "${规范输出}" == "${规范技能}"/* ]] || { print -u2 "二进制不在独立技能目录内：${输出}"; exit 1; }
[[ -x "${输出}" ]] || { print -u2 "构建结果不可执行：${输出}"; exit 1; }

if rg -n '/Users/macmini/Documents/codex/apple-music-playlist-helper' "${复制技能}"; then
  print -u2 '独立技能仍引用开发仓库路径'
  exit 1
fi

print '独立技能首次构建通过。'
