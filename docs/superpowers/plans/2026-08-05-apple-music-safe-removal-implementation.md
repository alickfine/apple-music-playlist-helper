# Apple Music 安全删除实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 为 Apple Music 播放列表技能增加按本机数据库 ID 精确删除、试运行和写后复核，并用它把“试音”整理为50首。

**架构：** 保持添加流程不变，新增独立 `RemovalWorkflow`。结构化 JXA 快照携带 `databaseId`；删除输入以 `databaseId + name + artist` 三项定位，驱动只删除指定用户播放列表中的唯一曲目引用。

**技术栈：** Swift 6、Swift Package Manager、XCTest、JXA/osascript、zsh。

## 全局约束

- 所有文档和用户可见消息使用中文。
- 删除前必须 dry-run，且用户已明确批准具体清单。
- 删除必须明确指定播放列表，并使用调用者私有临时目录中的一次性文件收据；伪造、快照变化、并发和重放均零写入。
- 不支持模糊删除、删除全部、跨列表删除、重排或删除音乐资料库文件。
- 每次实际删除后重新读取目标播放列表并按数据库 ID 复核。

---

### Task 1：删除数据模型与命令解析

**文件：**
- 修改：`Sources/PlaylistCore/Models.swift`
- 修改：`Sources/PlaylistCore/MusicAppClient.swift`
- 修改：`Sources/AMPlaylistCLIKit/CLIOptions.swift`
- 测试：`Tests/AMPlaylistCLIKitTests/CLIOptionsTests.swift`

**接口：**
- 产出：`CLICommand.add/remove`、`RemovalTrack`、`RemovalInputDocument`、带可选 `databaseID` 的 `PlaylistTrack`。

- [ ] 先增加测试：`remove --input` 可解析；`remove --create` 和 `remove --play-first` 被拒绝；`add` 旧行为不变。
- [ ] 运行 `swift test --filter CLIOptionsTests`，确认因缺少 `remove` 支持而失败。
- [ ] 实现最小命令枚举、参数约束和删除输入模型。
- [ ] 重新运行筛选测试，确认通过。

### Task 2：删除工作流

**文件：**
- 创建：`Sources/PlaylistCore/RemovalWorkflow.swift`
- 修改：`Sources/PlaylistCore/MusicAppClient.swift`
- 修改：`Sources/PlaylistCore/Models.swift`
- 测试：`Tests/PlaylistCoreTests/RemovalWorkflowTests.swift`
- 修改：`Tests/PlaylistCoreTests/PlaylistWorkflowTests.swift`

**接口：**
- 消费：`MusicAppClient.playlist(named:)` 与 `MusicAppClient.remove(_:from:)`。
- 产出：`RemovalWorkflow.run(document:options:) -> WorkflowReport`，成功状态为 `removed`。

- [ ] 写失败测试：dry-run 不写入；三项精确匹配才写入；缺失/歧义不写入；写后仍存在返回 `verification_failed`；单项失败继续处理。
- [ ] 运行 `swift test --filter RemovalWorkflowTests`，确认因类型和工作流不存在而失败。
- [ ] 实现最小删除工作流，并让报告退出码把 `removed` 视为成功。
- [ ] 更新添加流程假客户端以满足协议，运行 PlaylistCore 全部测试。

### Task 3：Music JXA 精确删除驱动

**文件：**
- 修改：`Sources/MusicAccessibilityDriver/MusicScriptReader.swift`
- 修改：`Sources/MusicAccessibilityDriver/MusicAccessibilityDriver.swift`
- 测试：`Tests/MusicAccessibilityDriverTests/MusicScriptReaderTests.swift`

**接口：**
- 产出：`MusicScriptReader.remove(track:from:)`，JXA 同时限定播放列表、`databaseId`、曲名和艺人且要求唯一匹配。

- [ ] 写失败测试：快照解析 `databaseId`；删除脚本包含三项精确条件、唯一性检查和 `app.delete`。
- [ ] 运行 `swift test --filter MusicScriptReaderTests`，确认旧实现不能满足新契约。
- [ ] 更新快照 JXA 和删除方法，通过驱动协议暴露。
- [ ] 运行 MusicAccessibilityDriver 测试并保持既有测试通过。

### Task 4：CLI、技能包装与中文规则

**文件：**
- 修改：`Sources/am-playlist/main.swift`
- 修改：`skill/apple-music-playlist/scripts/invoke.sh`
- 修改：`skill/apple-music-playlist/SKILL.md`
- 修改：`skill/apple-music-playlist/references/input-schema.md`
- 修改：`Tests/SkillPackageTests/invoke-routing.sh`
- 修改：`Tests/SkillPackageTests/package-contract.sh`

**接口：**
- `add` 解码 `TrackInputDocument` 并走原工作流；`remove` 解码 `RemovalInputDocument` 并走删除工作流。
- `remove` 不使用默认播放列表；dry-run 必须输出文件收据 token，实际删除必须对同一目录中的完整工件执行独占锁内原子消费。

- [ ] 先修改包装测试，要求 `remove` 参数原样路由，并要求危险命令仍被拒绝；运行测试确认失败。
- [ ] 实现 CLI 分流和 `invoke.sh` 白名单扩展。
- [ ] 更新技能规则：只有当前会话明确批准的精确清单才能删除，必须 dry-run，写后复核。
- [ ] 更新输入规范并运行全部技能包装测试。

### Task 5：同步、完整验证与真实整理

**文件：**
- 同步：`skill/apple-music-playlist/assets/helper/Sources/**`
- 安装：`/Users/macmini/.codex/skills/apple-music-playlist`

- [ ] 运行 `swift test`、所有 `Tests/SkillPackageTests/*.sh`、技能校验器和 `git diff --check`。
- [ ] 同步助手源代码到分发技能，执行本地技能安装并重新构建。
- [ ] 生成临时删除28首和新增20首 JSON；先只对删除28首 dry-run，确认全部唯一匹配且无失败。
- [ ] 使用同一私有收据目录实际删除28首，随后结构化读取并核验28首均不存在；任一删除失败立即停止，不执行新增。
- [ ] 删除核验全部通过后，才对新增20首 dry-run 并实际新增；不得先新增或退化为只新增到78首。
- [ ] 结构化读取“试音”，验证总数50、20首新增均存在、28首删除均不存在。
- [ ] 清理临时文件，检查 Git 差异并提交功能改动。
