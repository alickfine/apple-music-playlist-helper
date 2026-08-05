# Apple Music 曲目输入规范

仅在需要生成或检查执行层 JSON 时读取本文件。

## JSON 结构

```json
{
  "playlist": "目标播放列表",
  "tracks": [
    {
      "id": "123456789",
      "name": "曲名",
      "artist": "艺人",
      "url": "https://music.apple.com/ca/album/example/123456780?i=123456789"
    }
  ]
}
```

- `playlist` 可省略；若命令参数已经指定播放列表，JSON 中不得重复指定。
- `tracks` 保留用户请求的完整数量和顺序，不得截断或抽样。
- `id` 仅包含 ASCII 数字。
- `name` 和 `artist` 均不得为空。
- `url` 必须使用 `https://music.apple.com`。
- URL 必须且只能有一个 `i` 查询参数，并与 `id` 完全一致。

## 商店区域优先级

依次采用：用户在当前请求中明确指定的双字母区域、单曲链接中的路径区域、`APPLE_MUSIC_STOREFRONT`、用户配置文件、macOS 系统区域。仍无法确定时询问用户，不得使用固定开发者区域。

配置文件位置：`${XDG_CONFIG_HOME:-$HOME/.config}/apple-music-playlist/storefront`，内容为一行双字母区域代码。

有效的非默认示例包括：

- 加拿大：`ca`
- 日本：`jp`
- 巴西：`br`

这些仅是格式示例，不代表推荐或全局默认区域。
