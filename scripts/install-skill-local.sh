#!/bin/zsh
set -euo pipefail

仓库根目录="${0:A:h:h}"
源技能="${仓库根目录}/skill/apple-music-playlist"
目标根目录="${1:-${CODEX_HOME:-${HOME}/.codex}/skills}"
目标技能="${目标根目录}/apple-music-playlist"

[[ -f "${源技能}/SKILL.md" ]] || { print -u2 "源技能不完整：${源技能}"; exit 1; }
mkdir -p "${目标根目录}"
暂存目录=$(mktemp -d "${目标根目录}/.apple-music-playlist.install.XXXXXX")
旧目录=''

清理暂存() {
  [[ -d "${暂存目录}" ]] && rm -rf -- "${暂存目录}"
}
trap 清理暂存 EXIT

cp -R "${源技能}/." "${暂存目录}/"
find "${暂存目录}" -name '.build' -type d -prune -exec rm -rf -- {} +

if [[ -e "${目标技能}" ]]; then
  旧目录="${目标根目录}/.apple-music-playlist.previous.$$"
  [[ ! -e "${旧目录}" ]] || { print -u2 "安装备份路径已存在：${旧目录}"; exit 1; }
  mv "${目标技能}" "${旧目录}"
fi

if mv "${暂存目录}" "${目标技能}"; then
  [[ -z "${旧目录}" ]] || rm -rf -- "${旧目录}"
else
  [[ -z "${旧目录}" || ! -e "${旧目录}" ]] || mv "${旧目录}" "${目标技能}"
  exit 1
fi

trap - EXIT
print "技能已安装：${目标技能}"
