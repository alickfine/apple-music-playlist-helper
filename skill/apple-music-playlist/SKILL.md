---
name: apple-music-playlist
description: Use when a macOS user wants to find, recommend, check, deduplicate, add, create, or play songs in an Apple Music playlist using natural language, Apple Music links, catalog IDs, track names, artists, genres, moods, languages, eras, storefront regions, or an arbitrary-size song list.
---

# Apple Music 播放列表

## 核心原则

把自然语言请求转换为本机、可复核的 Apple Music 播放列表操作。所有写入都发生在当前 Mac 已登录的“音乐”账号中；不需要 Apple Developer Program、MusicKit 密钥或账号密码。

不得预设曲风、语言、年代、用途、商店区域或曲目数量。不得要求用户手写命令行。

## 运行条件

- 仅在 macOS 上使用，并确认“音乐”App 已登录可用账号。
- 首次调用执行层时运行 `scripts/bootstrap.sh`；它只在技能内部构建 Swift 助手。
- 缺少 Swift 时，说明需要 Xcode Command Line Tools，不代替用户下载安装。
- 缺少辅助功能或“音乐”自动化权限时，在写入前停止并说明系统授权路径。

## 解析自然语言请求

提取以下字段：

- 目标播放列表名称；
- 已列出的曲名、艺人、Apple Music 链接或目录 ID；
- 推荐所需的曲风、语言、年代、情绪、用途等当次条件；
- 商店区域；
- 数量；
- 是否只检查、直接添加、创建列表或播放首个新增曲目。

按以下规则处理缺失信息：

- 缺少播放列表名称：只询问播放列表名称，不猜测私人列表。
- 用户已经列出歌曲：数量就是清单长度，不再询问数量。
- 用户要求推荐但未给数量：询问一次期望数量；禁止自行默认 10 首、20 首或其他数量。
- 用户未给曲风等推荐条件：不添加隐含限制，也不为此追问。
- 曲目数量没有上限。大量输入可以内部拆批，但不得截断、抽样、减少或改变顺序。

## 确定 storefront

依次采用：

1. 当前请求明确指定的双字母区域；
2. Apple Music 链接中的 `music.apple.com/<区域>/`；
3. `APPLE_MUSIC_STOREFRONT` 或用户配置文件；
4. 当前 macOS 系统区域；
5. 仍无法确定时询问用户一次。

调用 `scripts/default-storefront.sh` 完成第 1 至第 4 步。不得固定使用中国区、美国区或技能开发者所在区域。多个链接来自不同区域时，逐首保留其区域，并在写入前报告可能的账号可用性差异。

## 解析和验证曲目

对完整 Apple Music 链接读取链接内的目录 ID、曲名和艺人。对曲名、艺人或推荐请求，优先使用可用的 Apple Music 目录连接器；没有连接器时，只搜索公开 `music.apple.com` 页面，并限定已确定的 storefront。

当前目录可用性可能变化；写入前必须实时核对。每首曲目必须得到：

- 仅含 ASCII 数字的目录 ID；
- 非空曲名和艺人；
- `https://music.apple.com` URL；
- 与目录 ID 完全相同的唯一 `i` 查询参数。

无法唯一确认、地区不可用或仅有同名近似结果时，将该曲目标为“未解析”，不要替换成其他地区、现场版、翻唱版或相似名称。

生成执行层 JSON 前读取 `references/input-schema.md`。临时文件使用 `mktemp -d` 创建，并在完成或失败后删除；不得包含凭据。

## 执行和确认

始终先通过下列机器入口执行试运行：

```bash
zsh scripts/invoke.sh add --playlist "目标列表" --input "临时输入.json" --dry-run --json
```

根据用户授权决定下一步：

- “查看”“检查”“先试运行”“不要修改”：返回试运行结果后停止，绝不创建、添加或播放。
- “直接添加”“确认添加”或等价表达：试运行后无需重复询问，直接对当前批次执行写入。
- 普通“加入”“放进”请求：试运行后集中汇报目标列表、新增数、重复数、未解析数和是否需要创建，只请求一次确认。
- 只有明确要求创建时才添加 `--create`。
- 只有明确要求播放时才添加 `--play-first`。

实际写入仍使用 `scripts/invoke.sh add`，去掉 `--dry-run` 并保留其余已经确认的参数。不要直接调用技能外的绝对路径或要求用户复制命令。

## 结果处理

按用户当前会话语言回复，并保持机器状态枚举不变。汇报：请求总数、已新增、已存在、未解析、失败和目标播放列表；只列出非成功项的简短原因，除非用户要求完整逐首报告。

执行层会按曲名和艺人规范化去重，并在每次添加后重新读取播放列表。只有写后复核存在才声称成功。单首失败不阻断后续曲目；大量任务保留已完成结果和剩余进度，重试时不要重复处理已复核成功的项目。

退出码含义：`0` 成功或全部重复；`2` 参数或输入错误；`3` 辅助功能权限不足；`4` 播放列表不存在；`5` 未找到、复核失败或其他执行错误。

## 安全边界

- 只处理当前请求涉及的播放列表和曲目。
- 不读取或保存 Apple ID 密码、Cookie、MusicKit 令牌、开发者密钥或付款信息。
- 不把完整播放列表发送到远程服务；去重和复核留在本机。
- 不使用截图、OCR、固定坐标或近似曲名点击。
- 不删除、移动、重排、下载或分享曲目；`scripts/invoke.sh` 也只接受 `add`。
