# Apple Music 播放列表助手

这是一个本机 macOS 自然语言技能和底层命令行助手：用户可以描述任意曲风、任意 Apple Music 商店区域和任意数量的歌曲，把尚未存在的曲目加入指定播放列表，或从一个明确播放列表安全删除当前会话已批准的精确曲目清单。它不需要 Apple Developer Program，也不把 Apple Music 账号凭据交给第三方服务。

## 自然语言 Skill

从 GitHub 获取并安装：

```bash
git clone https://github.com/alickfine/apple-music-playlist-helper.git
cd apple-music-playlist-helper
./scripts/install-skill-local.sh
```

安装完成后，新建一个 Codex 任务并直接用自然语言描述要查找的歌曲、商店区域、数量和目标播放列表。例如：

> 使用 Apple Music 技能，在中国区找 50 首覆盖人声、乐器、低频和动态的试音曲，去重后加入“试音”播放列表。

如果已经下载项目，也可以直接安装到 Codex 的默认全局技能目录：

```bash
./scripts/install-skill-local.sh
```

也可以安装到任意技能根目录：

```bash
./scripts/install-skill-local.sh /你选择的技能根目录
```

安装后可直接对 Codex 说：

- “把这些 Apple Music 链接加入我的通勤播放列表，先检查重复项。”
- “推荐 35 首适合晚餐的歌，加入晚餐列表。”
- “按加拿大区查找这些歌曲，直接加入收藏。”
- “只检查这 135 首哪些已在健身列表，不要修改。”
- “确认从试听删除这份精确的 28 首清单，核验后再新增这 20 首。”

技能不固定曲风、区域或数量。区域依次采用当次请求、Apple Music 链接、用户默认配置和 macOS 系统区域；仍无法确定时只询问一次。用户列出的歌曲全部保留；推荐请求没有数量时会询问，不会自行默认 10 首或 20 首。

技能目录完全自包含，首次使用时在技能内部构建 Swift 助手。安装过程不会预先携带二进制，不下载文件，也不修改 shell 配置。新安装的技能可能需要新建 Codex 任务后才出现在技能列表中。

## 工作方式与安全边界

工具通过“音乐”App 自带的脚本接口读取目标播放列表。添加首先打开准确 Apple Music URL；若直接页面未暴露目标目录 ID，则通过 Music 搜索框和回车进入完整结果，先匹配目标曲目或精确专辑的 `TopSearchLockup`/`SquareLockup` 目录 ID，再在专辑页匹配目标曲目的 `AlbumTrackLockup` 目录 ID。两次精确校验通过后才会打开该曲目的“更多”并加入播放列表。若目标是 Music 不显示在该子菜单中的空播放列表，则还必须在同一 AX 快照中确认精确曲目容器和完整播放列表名，然后只允许把资料库中“曲名＋艺人”唯一匹配的一项复制到该列表；候选为零或多项时失败关闭。删除只通过结构化 JXA 在一个明确播放列表内按本机数据库 ID、曲名和艺人三项逐字唯一匹配曲目引用。

添加和删除都不使用截图、OCR、固定坐标或近似曲名。搜索回退不会把目标曲目替换为其他目录 ID、现场版、翻唱版或其他区服版本；任一精确 ID 不可见时返回 `not_found`。

默认情况下它：

- 不创建不存在的播放列表；只有 `--create` 会创建。
- 不自动播放；只有 `--play-first` 会播放首个新增曲目。
- 不执行模糊、整表、跨播放列表或资料库文件删除，也不移动、重排、下载或分享曲目。
- 不修改其他播放列表，也不输出未请求的资料库内容。
- 每次添加后重新读取目标播放列表，复核成功后才报告“已添加”。
- 删除必须先 dry-run，实际执行要求当前会话明确批准、同一私有临时收据目录和原样一次性 token；每次删除后重新读取同一列表，复核成功后才报告“已删除”。

## 系统要求与权限

- macOS 26 或更高版本。
- Xcode Command Line Tools，以及 Swift 6.2 或更高版本。
- 已登录并可正常使用的“音乐”App。
- “系统设置”→“隐私与安全性”→“辅助功能”中，允许运行 `am-playlist` 的终端或 Codex。
- 首次读取或控制“音乐”时，macOS 可能要求在“自动化”中允许对应终端控制“音乐”。

工具只做无提示权限检查，不会主动弹出或代替你确认系统授权。

## 命令行高级用法：构建与安装

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

## 添加输入格式

输入文件必须是 UTF-8 JSON。`playlist` 可省略；若命令行已经提供 `--playlist`，JSON 中不得再次提供。

```json
{
  "playlist": "试音",
  "tracks": [
    {
      "id": "905228611",
      "name": "被遗忘的时光",
      "artist": "蔡琴",
      "url": "https://music.apple.com/ca/song/905228611?i=905228611"
    }
  ]
}
```

`id` 必须只含 ASCII 数字；`url` 必须使用 `https://music.apple.com`，并且唯一的 `i` 参数必须与 `id` 完全一致。写入前应确认曲目在用户所用 Apple Music 商店区域中仍可搜索。

## 删除输入格式

删除 JSON 每项必须来自同一播放列表的当前结构化快照：

```json
{
  "playlist": "试音",
  "tracks": [
    {
      "databaseId": "123456789",
      "name": "曲名",
      "artist": "艺人"
    }
  ]
}
```

`remove` 必须通过 JSON 的 `playlist` 或 `--playlist` 明确指定播放列表，不能使用默认列表。三字段必须逐字唯一匹配；空清单、通配符、近似名称、类别、位置和“全部重复项”都不会被解释成删除条件。

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

安全删除使用由调用者创建的私有临时目录。dry-run 的 JSON 含一次性 `removalReceiptToken`；下面在进程变量中捕获它，不要打印或写入日志：

```bash
临时目录=$(mktemp -d)
trap 'rm -rf -- "$临时目录"' EXIT
收据目录="$临时目录/receipts"
mkdir -m 700 "$收据目录"

试运行JSON=$(am-playlist remove --playlist "试音" --input "$临时目录/removals.json" \
  --receipt-dir "$收据目录" --dry-run --json)
收据令牌=$(printf '%s' "$试运行JSON" | plutil -extract removalReceiptToken raw -o - -- -)

am-playlist remove --playlist "试音" --input "$临时目录/removals.json" \
  --receipt-dir "$收据目录" --approved --receipt-token "$收据令牌" --json
unset 收据令牌 试运行JSON
```

实际删除前必须人工核对 dry-run 清单与当前会话批准的清单完全一致。收据目录必须是当前用户拥有、group/other 无权限且非符号链接的目录。token 只能使用一次；伪造、重放、快照变化或文件锁冲突都会零写入。

全部支持的参数：

- `add`：添加和去重；未提供播放列表时保留历史默认“试音”。
- `remove`：只删除当前会话批准的单列表精确清单；必须明确播放列表。
- `--input <路径>`：必需，输入 JSON 文件。
- `--playlist <名称>`：指定目标播放列表；不能与 JSON 的 `playlist` 同时使用。`remove` 必须由二者之一提供。
- `--create`：目标不存在时创建；默认不创建。
- `--dry-run`：只读取、校验并报告计划，不执行添加、删除或播放；删除试运行还必须带 `--json` 和 `--receipt-dir`。
- `--play-first`：添加结束后播放首个新增曲目。
- `--timeout <秒>`：等待目录 ID 出现在辅助功能树中的正整数秒数，默认 8 秒。
- `--json`：输出机器可读 JSON；否则输出中文文本。
- `--receipt-dir <路径>`：仅用于删除；调用者创建的私有临时收据目录。
- `--approved`：仅用于实际删除，表示当前会话已批准具体清单。
- `--receipt-token <令牌>`：仅用于实际删除，必须原样使用同目录 dry-run 返回的一次性 token。

## 退出码

- `0`：成功，或所有输入曲目均已存在。
- `2`：命令参数、输入文件或 JSON 格式错误。
- `3`：缺少辅助功能权限。
- `4`：目标播放列表不存在且未指定 `--create`。
- `5`：曲目未找到、写后复核失败或其他执行错误。

## 常见问题

“权限不足”：到“系统设置”→“隐私与安全性”→“辅助功能”授权实际运行命令的终端或 Codex；若脚本读取失败，再检查同一页面附近的“自动化”权限。

“未找到与目录 ID 准确匹配的曲目”：先在“音乐”中确认对应区域仍能搜索该单曲。工具已经尝试准确 URL 和目录 ID 双重校验的搜索回退；仍失败时不会退回到近似曲名或其他版本。

“播放列表不存在”：先在“音乐”中手动创建，或在明确需要时添加 `--create`。

“写后复核未找到曲目”：工具已经停止继续声称成功；请在“音乐”中检查网络、目录可用性和播放列表状态后重试。

“收据目录无效”：重新使用 `mktemp -d` 创建当前用户私有目录，并确保它不是符号链接且没有 group/other 权限。不要复制、长期保存或共享收据文件和 token。

混合删除和新增时，必须先完成删除 dry-run、实际删除和结构化核验；任何删除失败都停止新增。只有 28 首删除全部核验通过后，才对 20 首新增 dry-run 并实际添加，避免只新增导致列表达到 78 首。

## 开发验证

```bash
swift test
swift build -c release
zsh Tests/SkillPackageTests/package-contract.sh
zsh Tests/SkillPackageTests/portable-bootstrap.sh
```

自动测试使用注入的假客户端，不会启动或修改“音乐”App。
