#!/bin/zsh
set -euo pipefail

仓库根目录="${0:A:h:h:h}"
技能目录="${仓库根目录}/skill/apple-music-playlist"

[[ -f "${技能目录}/SKILL.md" ]] || { print -u2 '缺少 SKILL.md'; exit 1; }
[[ -f "${技能目录}/agents/openai.yaml" ]] || { print -u2 '缺少 agents/openai.yaml'; exit 1; }
[[ ! -e "${技能目录}/README.md" ]] || { print -u2 '技能分发目录不得包含 README.md'; exit 1; }
[[ -f "${技能目录}/assets/helper/Sources/PlaylistCore/FileRemovalReceiptStore.swift" ]] || {
  print -u2 '技能分发执行层缺少文件型删除收据存储'
  exit 1
}
[[ -f "${技能目录}/assets/helper/Sources/PlaylistCore/RemovalWorkflow.swift" ]] || {
  print -u2 '技能分发执行层缺少安全删除工作流'
  exit 1
}

名称=$(awk '/^---$/{section++; next} section==1 && /^name:/{sub(/^name:[[:space:]]*/, ""); print; exit}' "${技能目录}/SKILL.md")
[[ "${名称}" == 'apple-music-playlist' ]] || { print -u2 "技能名错误：${名称}"; exit 1; }

字段=$(awk '/^---$/{section++; next} section==1 && /^[a-zA-Z0-9_-]+:/{sub(/:.*/, ""); print}' "${技能目录}/SKILL.md" | LC_ALL=C sort | tr '\n' ' ')
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

输入规范="${技能目录}/references/input-schema.md"
添加小节=$(awk '/^## 添加 JSON 结构$/{active=1; next} /^## /{active=0} active' "${输入规范}")
删除小节=$(awk '/^## 删除 JSON 结构$/{active=1; next} /^## /{active=0} active' "${输入规范}")
if print -r -- "${添加小节}" | rg -q 'remove.*必须.*playlist|playlist.*remove.*必须'; then
  print -u2 '添加 JSON 小节混入了 remove 的显式播放列表规则'
  exit 1
fi
if ! print -r -- "${删除小节}" | rg -q 'remove.*必须.*playlist|playlist.*remove.*必须'; then
  print -u2 '删除 JSON 小节缺少 remove 的显式播放列表规则'
  exit 1
fi

if ! rg -q 'TopSearchLockup' "${技能目录}/SKILL.md" ||
   ! rg -q 'AlbumTrackLockup' "${技能目录}/SKILL.md"; then
  print -u2 '技能缺少搜索结果与专辑页的目录 ID 双重校验说明'
  exit 1
fi
if ! rg -q '不使用截图、OCR、固定坐标' "${技能目录}/SKILL.md"; then
  print -u2 '技能缺少可执行的无视觉坐标安全边界'
  exit 1
fi
if ! rg -q '不得.*替换.*目录 ID|不得.*目录 ID.*替换' "${技能目录}/SKILL.md"; then
  print -u2 '技能缺少禁止目录版本替换的安全边界'
  exit 1
fi
if ! rg -q '空播放列表' "${技能目录}/SKILL.md" ||
   ! rg -q '候选恰好为一项' "${技能目录}/SKILL.md"; then
  print -u2 '技能缺少空播放列表的精确 AX 校验与唯一候选桥接规则'
  exit 1
fi

while IFS= read -r 文件; do
  if file "${文件}" | rg -q 'Mach-O'; then
    print -u2 "技能初始包包含预编译二进制：${文件}"
    exit 1
  fi
done < <(find "${技能目录}" -type f)

print '技能包契约通过。'
