# Apple Music 精确搜索回退与空列表桥接验收报告

## 结论

2026-08-05 已完成精确搜索回退、空播放列表写入桥接、可分发 Skill 同步与本机安装。真实 Music 账号验收通过：目录 ID `905228635` 对应的《渡口》—蔡琴首次返回 `added`，第二次返回 `skipped_duplicate`；临时播放列表最终且仅含这一首曲目。

## 安全链

1. 优先打开经过输入校验的 Apple Music URL，并在 AX 树中寻找目标目录 ID。
2. 直达页面未就绪时，进入 Music 搜索页，写入“曲名 艺人”后直接回车；不使用向下键误选最近搜索。
3. 搜索结果必须命中目标曲目 `TopSearchLockup`，或命中 URL 中精确专辑 ID 的 `TopSearchLockup`/`SquareLockup`。
4. 专辑页必须再次命中目标曲目的 `AlbumTrackLockup` 目录 ID。
5. 普通播放列表只选择完整同名菜单项。
6. 空播放列表未出现在子菜单时，必须同时确认精确曲目容器和边栏完整同名列表；随后只复制资料库中曲名、艺人逐字匹配且唯一的一项。零项或多项均失败关闭。
7. 每次写入后重新读取目标播放列表；未出现目标曲目时返回 `verification_failed`，不报告成功。

## 自动化验证

- `swift test`：95 项测试全部通过。
- `swift build -c release`：通过。
- `Tests/SkillPackageTests`：调用路由、包契约、独立首次构建、删除命令拒绝、storefront 解析共 5 项通过。
- `npx --yes skills-ref validate skill/apple-music-playlist`：`Valid skill`。
- 分发 Skill 与 `/Users/macmini/.codex/skills/apple-music-playlist` 安装副本逐文件一致。

## 真实 Music 验收

- 播放列表：`Apple Music Skill 测试 2026-08-05`。
- 首次添加：`added`，消息为“已添加并通过写后复核。”
- 第二次相同请求：`skipped_duplicate`，消息为“播放列表中已存在，已跳过。”
- 最终结构化回读：播放列表同名实例 1 个，曲目数 1；内容为《渡口》—蔡琴。
- 临时播放列表按批准保留，未执行删除。
