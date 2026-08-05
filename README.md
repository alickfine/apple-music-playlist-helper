# Apple Music 播放列表助手

这是一个本机 macOS 命令行工具：输入准确的 Apple Music 目录 ID、曲名、艺人和国区链接后，把尚未存在的曲目依次加入指定播放列表。它不需要 Apple Developer Program，也不把 Apple Music 账号凭据交给第三方服务。

## 工作方式与安全边界

工具通过“音乐”App 自带的脚本接口读取目标播放列表，通过 macOS 辅助功能树定位目录 ID 完全一致的曲目，再按播放列表完整名称执行添加。它不使用截图、OCR、固定坐标或近似曲名。

默认情况下它：

- 不创建不存在的播放列表；只有 `--create` 会创建。
- 不自动播放；只有 `--play-first` 会播放首个新增曲目。
- 不删除、移动、重排、下载或分享曲目。
- 不修改其他播放列表，也不输出未请求的资料库内容。
- 每次添加后重新读取目标播放列表，复核成功后才报告“已添加”。

## 系统要求与权限

- macOS 26 或更高版本。
- Xcode Command Line Tools，以及 Swift 6.2 或更高版本。
- 已登录并可正常使用的“音乐”App。
- “系统设置”→“隐私与安全性”→“辅助功能”中，允许运行 `am-playlist` 的终端或 Codex。
- 首次读取或控制“音乐”时，macOS 可能要求在“自动化”中允许对应终端控制“音乐”。

工具只做无提示权限检查，不会主动弹出或代替你确认系统授权。

## 构建与安装

在项目目录运行：

```bash
swift build -c release
./scripts/install-local.sh
```

默认安装到 `~/.local/bin/am-playlist`。也可指定目标目录：

```bash
./scripts/install-local.sh /你选择的目录
```

安装脚本不会下载文件、不会使用管理员权限，也不会修改 shell 配置。若 `~/.local/bin` 尚未加入 `PATH`，可直接使用完整路径运行。

卸载只需删除已安装的单个可执行文件，例如：

```bash
rm "$HOME/.local/bin/am-playlist"
```

## 输入格式

输入文件必须是 UTF-8 JSON。`playlist` 可省略；若命令行已经提供 `--playlist`，JSON 中不得再次提供。

```json
{
  "playlist": "试音",
  "tracks": [
    {
      "id": "905228611",
      "name": "被遗忘的时光",
      "artist": "蔡琴",
      "url": "https://music.apple.com/cn/song/905228611?i=905228611"
    }
  ]
}
```

`id` 必须只含 ASCII 数字；`url` 必须使用 `https://music.apple.com`，并且唯一的 `i` 参数必须与 `id` 完全一致。建议先确认曲目在中国大陆 Apple Music 目录中仍可搜索。

## 使用方法

先执行只读试运行：

```bash
am-playlist add --input Fixtures/tracks.example.json --dry-run
```

明确指定播放列表并输出 JSON：

```bash
am-playlist add --playlist "试音" --input Fixtures/tracks.example.json --dry-run --json
```

确认结果后实际添加：

```bash
am-playlist add --playlist "试音" --input Fixtures/tracks.example.json
```

全部支持的参数：

- `add`：唯一支持的子命令。
- `--input <路径>`：必需，输入 JSON 文件。
- `--playlist <名称>`：可选，指定目标播放列表；不能与 JSON 的 `playlist` 同时使用。
- `--create`：目标不存在时创建；默认不创建。
- `--dry-run`：只读取、校验并报告计划，不执行添加或播放。
- `--play-first`：添加结束后播放首个新增曲目。
- `--timeout <秒>`：等待目录 ID 出现在辅助功能树中的正整数秒数，默认 8 秒。
- `--json`：输出机器可读 JSON；否则输出中文文本。

## 退出码

- `0`：成功，或所有输入曲目均已存在。
- `2`：命令参数、输入文件或 JSON 格式错误。
- `3`：缺少辅助功能权限。
- `4`：目标播放列表不存在且未指定 `--create`。
- `5`：曲目未找到、写后复核失败或其他执行错误。

## 常见问题

“权限不足”：到“系统设置”→“隐私与安全性”→“辅助功能”授权实际运行命令的终端或 Codex；若脚本读取失败，再检查同一页面附近的“自动化”权限。

“未找到与目录 ID 准确匹配的曲目”：先在“音乐”中确认该国区链接能打开对应单曲，并确认页面已加载完成。工具不会退回到近似曲名点击。

“播放列表不存在”：先在“音乐”中手动创建，或在明确需要时添加 `--create`。

“写后复核未找到曲目”：工具已经停止继续声称成功；请在“音乐”中检查网络、目录可用性和播放列表状态后重试。

## 开发验证

```bash
swift test
swift build -c release
```

自动测试使用注入的假客户端，不会启动或修改“音乐”App。
