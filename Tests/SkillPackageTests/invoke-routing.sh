#!/bin/zsh
set -euo pipefail

仓库根目录="${0:A:h:h:h}"
临时根目录=$(mktemp -d)
trap 'rm -rf -- "${临时根目录}"' EXIT
cp -R "${仓库根目录}/skill/apple-music-playlist" "${临时根目录}/apple-music-playlist"
技能目录="${临时根目录}/apple-music-playlist"
假二进制="${技能目录}/assets/helper/fake-am-playlist"

print '#!/bin/zsh' > "${假二进制}"
print 'printf "%s\\n" "$@"' >> "${假二进制}"
chmod +x "${假二进制}"

print '#!/bin/zsh' > "${技能目录}/scripts/bootstrap.sh"
print 'print -r -- "${0:A:h:h}/assets/helper/fake-am-playlist"' >> "${技能目录}/scripts/bootstrap.sh"
chmod +x "${技能目录}/scripts/bootstrap.sh"

输出=$(zsh "${技能目录}/scripts/invoke.sh" add --playlist '我的 列表' --input '/tmp/歌曲 清单.json' --dry-run --json)
预期=$'add\n--playlist\n我的 列表\n--input\n/tmp/歌曲 清单.json\n--dry-run\n--json'
[[ "${输出}" == "${预期}" ]] || { print -u2 "参数未原样传递：\n${输出}"; exit 1; }

删除输出=$(zsh "${技能目录}/scripts/invoke.sh" remove --playlist '我的 列表' \
  --input '/tmp/删除 清单.json' --receipt-dir '/tmp/收据 目录' --dry-run --json)
删除预期=$'remove\n--playlist\n我的 列表\n--input\n/tmp/删除 清单.json\n--receipt-dir\n/tmp/收据 目录\n--dry-run\n--json'
[[ "${删除输出}" == "${删除预期}" ]] || { print -u2 "删除参数未原样传递：\n${删除输出}"; exit 1; }

for 危险命令 in delete-library move reorder share download; do
  set +e
  zsh "${技能目录}/scripts/invoke.sh" "${危险命令}" --playlist '我的 列表' >/dev/null 2>"${临时根目录}/错误"
  退出码=$?
  set -e
  [[ "${退出码}" == 2 ]] || { print -u2 "危险命令 ${危险命令} 应退出 2，实际为 ${退出码}"; exit 1; }
  rg -q '仅支持 add 和 remove' "${临时根目录}/错误"
done

print '技能调用参数路由测试通过。'
