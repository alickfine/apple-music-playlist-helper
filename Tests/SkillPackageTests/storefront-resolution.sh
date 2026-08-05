#!/bin/zsh
set -euo pipefail

仓库根目录="${0:A:h:h:h}"
脚本="${仓库根目录}/skill/apple-music-playlist/scripts/default-storefront.sh"
临时配置=$(mktemp -d)
trap 'rm -rf -- "${临时配置}"' EXIT

结果=$(XDG_CONFIG_HOME="${临时配置}" APPLE_MUSIC_STOREFRONT=de APPLE_LOCALE=pt_BR zsh "${脚本}" --explicit CA --url 'https://music.apple.com/us/song/1?i=1')
[[ "${结果}" == 'ca' ]] || { print -u2 "显式区域优先级错误：${结果}"; exit 1; }

结果=$(XDG_CONFIG_HOME="${临时配置}" APPLE_MUSIC_STOREFRONT=gb APPLE_LOCALE=pt_BR zsh "${脚本}" --url 'https://music.apple.com/JP/album/example/1?i=2')
[[ "${结果}" == 'jp' ]] || { print -u2 "链接区域优先级错误：${结果}"; exit 1; }

结果=$(XDG_CONFIG_HOME="${临时配置}" APPLE_MUSIC_STOREFRONT=DE APPLE_LOCALE=pt_BR zsh "${脚本}")
[[ "${结果}" == 'de' ]] || { print -u2 "环境默认区域错误：${结果}"; exit 1; }

mkdir -p "${临时配置}/apple-music-playlist"
print 'FR' > "${临时配置}/apple-music-playlist/storefront"
结果=$(XDG_CONFIG_HOME="${临时配置}" APPLE_LOCALE=pt_BR zsh "${脚本}")
[[ "${结果}" == 'fr' ]] || { print -u2 "配置默认区域错误：${结果}"; exit 1; }

rm "${临时配置}/apple-music-playlist/storefront"
结果=$(XDG_CONFIG_HOME="${临时配置}" APPLE_LOCALE=pt_BR zsh "${脚本}")
[[ "${结果}" == 'br' ]] || { print -u2 "系统区域映射错误：${结果}"; exit 1; }

set +e
XDG_CONFIG_HOME="${临时配置}" APPLE_LOCALE='' zsh "${脚本}" >/dev/null 2>"${临时配置}/错误"
退出码=$?
set -e
[[ "${退出码}" == 4 ]] || { print -u2 "无法确定区域时应退出 4，实际为 ${退出码}"; exit 1; }
rg -q '无法确定 Apple Music 商店区域' "${临时配置}/错误"

set +e
XDG_CONFIG_HOME="${临时配置}" APPLE_LOCALE=pt_BR zsh "${脚本}" --explicit USA >/dev/null 2>"${临时配置}/无效"
退出码=$?
set -e
[[ "${退出码}" == 4 ]] || { print -u2 "无效显式区域应退出 4，实际为 ${退出码}"; exit 1; }

print 'storefront 优先级与无默认区域测试通过。'
