#!/bin/zsh
set -euo pipefail

显式区域=''
目录链接=''

while (( $# > 0 )); do
  case "$1" in
    --explicit)
      (( $# >= 2 )) || { print -u2 '参数 --explicit 缺少区域代码。'; exit 4; }
      显式区域="$2"
      shift 2
      ;;
    --url)
      (( $# >= 2 )) || { print -u2 '参数 --url 缺少 Apple Music 链接。'; exit 4; }
      目录链接="$2"
      shift 2
      ;;
    *)
      print -u2 "未知参数：$1"
      exit 2
      ;;
  esac
done

规范区域() {
  local 候选="$1"
  [[ "${候选}" == [A-Za-z][A-Za-z] ]] || return 1
  print -r -- "${(L)候选}"
}

if [[ -n "${显式区域}" ]]; then
  规范区域 "${显式区域}" || { print -u2 "无效的显式商店区域：${显式区域}"; exit 4; }
  exit 0
fi

if [[ -n "${目录链接}" ]]; then
  if [[ "${目录链接}" =~ '^https://music\.apple\.com/([A-Za-z]{2})(/|$)' ]]; then
    规范区域 "${match[1]}"
    exit 0
  fi
  print -u2 'Apple Music 链接未包含有效的双字母商店区域。'
  exit 4
fi

if [[ -n "${APPLE_MUSIC_STOREFRONT:-}" ]]; then
  规范区域 "${APPLE_MUSIC_STOREFRONT}" || {
    print -u2 "无效的 APPLE_MUSIC_STOREFRONT：${APPLE_MUSIC_STOREFRONT}"
    exit 4
  }
  exit 0
fi

配置根目录="${XDG_CONFIG_HOME:-${HOME}/.config}"
配置文件="${配置根目录}/apple-music-playlist/storefront"
if [[ -f "${配置文件}" ]]; then
  IFS= read -r 配置区域 < "${配置文件}" || true
  规范区域 "${配置区域}" || { print -u2 "默认区域配置无效：${配置文件}"; exit 4; }
  exit 0
fi

if (( ${+APPLE_LOCALE} )); then
  系统区域="${APPLE_LOCALE}"
else
  系统区域=$(defaults read -g AppleLocale 2>/dev/null || true)
fi

if [[ "${系统区域}" =~ '[_-]([A-Za-z]{2})(@|$)' ]]; then
  规范区域 "${match[1]}"
  exit 0
fi

print -u2 '无法确定 Apple Music 商店区域；请在请求中指定区域，或配置默认 storefront。'
exit 4
