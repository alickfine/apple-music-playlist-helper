#!/bin/zsh
set -euo pipefail

仓库根目录="${0:A:h:h:h}"
技能目录="${仓库根目录}/skill/apple-music-playlist"

[[ -f "${技能目录}/SKILL.md" ]] || { print -u2 '缺少 SKILL.md'; exit 1; }
[[ -f "${技能目录}/agents/openai.yaml" ]] || { print -u2 '缺少 agents/openai.yaml'; exit 1; }
[[ ! -e "${技能目录}/README.md" ]] || { print -u2 '技能分发目录不得包含 README.md'; exit 1; }

名称=$(awk '/^---$/{区块++; next} 区块==1 && /^name:/{sub(/^name:[[:space:]]*/, ""); print; exit}' "${技能目录}/SKILL.md")
[[ "${名称}" == 'apple-music-playlist' ]] || { print -u2 "技能名错误：${名称}"; exit 1; }

字段=$(awk '/^---$/{区块++; next} 区块==1 && /^[a-zA-Z0-9_-]+:/{sub(/:.*/, ""); print}' "${技能目录}/SKILL.md" | LC_ALL=C sort | tr '\n' ' ')
[[ "${字段}" == 'description name ' ]] || { print -u2 "frontmatter 只能包含 name 和 description，实际为：${字段}"; exit 1; }

if rg -n '/Users/macmini|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|sk-[A-Za-z0-9]{20,}' "${技能目录}"; then
  print -u2 '技能包含个人路径或敏感内容'
  exit 1
fi

待办一='TO''DO'
待办二='TB''D'
if rg -n "${待办一}|${待办二}|待补充|稍后实现|占位内容" "${技能目录}"; then
  print -u2 '技能包含占位标记'
  exit 1
fi

while IFS= read -r 文件; do
  if file "${文件}" | rg -q 'Mach-O'; then
    print -u2 "技能初始包包含预编译二进制：${文件}"
    exit 1
  fi
done < <(find "${技能目录}" -type f)

print '技能包契约通过。'
