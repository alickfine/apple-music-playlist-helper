# Apple Music 精确搜索回退实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 Swift 助手中加入无截图、无固定坐标、由目录 ID 双重校验保护的 Music 搜索回退，并完成可公开分发的第一版验收。

**Architecture:** 保留准确 URL 直接定位作为快速路径；若目标 `AlbumTrackLockup` 未出现，则由可注入的辅助功能交互接口打开 Music 搜索、写入“曲名 艺人”、通过键盘进入完整结果，再按目标曲目 ID 或链接中的精确专辑 ID 进入专辑。专辑页必须再次出现目标曲目 ID，之后才能点击“更多”和精确播放列表菜单项；`PlaylistWorkflow` 继续负责写后回读。

**Tech Stack:** Swift 6.3、Foundation、AppKit、ApplicationServices、XCTest、zsh、Agent Skills `skills-ref`。

## Global Constraints

- 仅支持 macOS 本机当前已登录的 Music 账号，不需要 Apple Developer Program 或 MusicKit 密钥。
- 禁止截图、OCR、固定坐标和目录版本自动替换。
- 所有写入必须由完整数字目录 ID 触发；播放列表名称必须逐字匹配。
- 单首总超时由现有 `--timeout` 控制，回退不能无限延长。
- 不新增删除、重排、下载、收藏、分享或登录能力。
- 中文文档优先；代码符号、状态枚举、命令和产品名保留英文。
- 顶层源码与 `skill/apple-music-playlist/assets/helper` 必须完全同步。

---

### Task 1: URL 专辑 ID 与搜索结果精确匹配器

**Files:**
- Modify: `Sources/PlaylistCore/Models.swift`
- Modify: `Sources/MusicAccessibilityDriver/AccessibilityMatching.swift`
- Test: `Tests/PlaylistCoreTests/TrackValidationTests.swift`
- Test: `Tests/MusicAccessibilityDriverTests/AccessibilityMatchingTests.swift`

**Interfaces:**
- Produces: `CatalogTrack.albumID: String?`
- Produces: `AccessibilityMatcher.searchField(in:) -> AccessibilityPath?`
- Produces: `AccessibilityMatcher.topSearchResult(catalogID:in:) -> AccessibilityPath?`
- Produces: `AccessibilityMatcher.albumSearchResult(albumID:in:) -> AccessibilityPath?`

- [ ] **Step 1: 写 URL 与匹配器失败测试**

```swift
func testCatalogTrackExtractsNumericAlbumIDFromValidatedURL() throws {
    let track = try input.validated()
    XCTAssertEqual(track.albumID, "905228605")
}

func testFindsOnlyExactTopSearchCatalogID() {
    XCTAssertEqual(AccessibilityMatcher.topSearchResult(catalogID: "905228635", in: tree), expectedPath)
    XCTAssertNil(AccessibilityMatcher.topSearchResult(catalogID: "90522863", in: tree))
}
```

- [ ] **Step 2: 运行定向测试并确认 RED**

Run: `swift test --filter 'TrackValidationTests|AccessibilityMatchingTests'`

Expected: 编译失败，提示 `albumID`、`searchField`、`topSearchResult` 或 `albumSearchResult` 尚不存在。

- [ ] **Step 3: 实现最小纯函数**

```swift
public extension CatalogTrack {
    var albumID: String? {
        url.pathComponents.last(where: { !$0.isEmpty && $0.allSatisfy(\.isNumber) })
    }
}
```

匹配器只检查对应锁定节点标识符中的完整数字 token，并返回节点自身路径；搜索框必须是 `AXTextField` 或 `AXSearchField` 且可设置。

- [ ] **Step 4: 运行定向测试并确认 GREEN**

Run: `swift test --filter 'TrackValidationTests|AccessibilityMatchingTests'`

Expected: 全部通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/PlaylistCore/Models.swift Sources/MusicAccessibilityDriver/AccessibilityMatching.swift Tests/PlaylistCoreTests/TrackValidationTests.swift Tests/MusicAccessibilityDriverTests/AccessibilityMatchingTests.swift
git commit -m "feat: match exact Music search results"
```

### Task 2: 可测试的 Music 搜索交互接口

**Files:**
- Modify: `Sources/MusicAccessibilityDriver/AccessibilityTree.swift`
- Modify: `Sources/MusicAccessibilityDriver/MusicAccessibilityDriver.swift`
- Test: `Tests/MusicAccessibilityDriverTests/MusicAccessibilityDriverTests.swift`

**Interfaces:**
- Produces: `enum MusicKeyStroke: Equatable, Sendable { case commandF, downArrow, returnKey }`
- Produces: `AccessibilityProviding.setValue(_:path:) throws`
- Produces: `AccessibilityProviding.send(_:) throws`

- [ ] **Step 1: 写交互接口失败测试**

```swift
func testSearchInteractionWritesExactQueryAndUsesKeyboardNavigation() async throws {
    // 直接页为空，随后出现搜索框、精确结果、专辑曲目和菜单。
    let result = try await driver.add(track, to: "试音", timeout: .seconds(1))
    XCTAssertEqual(provider.setValues, [.init(value: "被遗忘的时光 蔡琴", path: searchPath)])
    XCTAssertEqual(provider.sentKeys, [.commandF, .downArrow, .returnKey])
    XCTAssertEqual(result, .submitted)
}
```

- [ ] **Step 2: 运行测试并确认 RED**

Run: `swift test --filter MusicAccessibilityDriverTests`

Expected: 编译失败，提示协议没有 `setValue`、`send` 或 `MusicKeyStroke`。

- [ ] **Step 3: 实现协议与生产适配器**

`AXMusicAccessibilityProvider.setValue` 重新解析路径并调用 `AXUIElementSetAttributeValue(..., kAXValueAttribute, ...)`；`send` 只生成已枚举的三种 `CGEvent` 键盘事件，并先激活 `com.apple.Music`。任何路径失效、属性不可写或事件创建失败都抛出中文可诊断错误。

- [ ] **Step 4: 运行测试并确认 GREEN**

Run: `swift test --filter MusicAccessibilityDriverTests`

Expected: 新接口测试和旧驱动测试全部通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/MusicAccessibilityDriver/AccessibilityTree.swift Sources/MusicAccessibilityDriver/MusicAccessibilityDriver.swift Tests/MusicAccessibilityDriverTests/MusicAccessibilityDriverTests.swift
git commit -m "feat: add testable Music search controls"
```

### Task 3: 有界精确搜索回退状态机

**Files:**
- Modify: `Sources/MusicAccessibilityDriver/MusicAccessibilityDriver.swift`
- Modify: `Tests/MusicAccessibilityDriverTests/MusicAccessibilityDriverTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `albumID` 与搜索结果匹配器。
- Consumes: Task 2 的 `setValue` 和 `send`。
- Produces: `MusicAccessibilityDriver.add(_:to:timeout:)` 的直接 URL + 搜索回退行为，返回值仍为 `AddTrackOutcome`。

- [ ] **Step 1: 写回退状态机失败测试**

覆盖以下树序列：

```swift
[
    emptyDirectPage,
    searchFieldTree,
    topSearchTrackTree,
    albumTrackTree,
    playlistMenuTree
]
```

另写精确专辑回退、错误目录 ID、专辑二次校验缺失、菜单缺失和总期限耗尽测试。每项都断言实际按压路径和键盘序列，证明没有相似结果点击。

- [ ] **Step 2: 运行测试并确认 RED**

Run: `swift test --filter MusicAccessibilityDriverTests`

Expected: 新回退测试返回 `notFound` 或调用序列不匹配。

- [ ] **Step 3: 实现最小状态机**

```swift
if let more = await pollForTrackMore(until: directDeadline) {
    return try submit(more, playlist: playlist)
}
try accessibility.send(.commandF)
guard let field = await pollForSearchField(until: deadline) else { return .notFound }
try accessibility.setValue("\(track.name) \(track.artist)", path: field)
try accessibility.send(.downArrow)
try accessibility.send(.returnKey)
guard let result = await pollForExactResult(trackID: track.id, albumID: track.albumID, until: deadline) else { return .notFound }
try accessibility.press(path: result)
guard let more = await pollForTrackMore(until: deadline) else { return .notFound }
return try submit(more, playlist: playlist)
```

实现时把重复轮询抽成文件内私有函数；每次页面转换后重新快照，不跨页面复用路径。直接阶段只使用总时限的一小部分，确保搜索阶段至少获得一次条件轮询机会。

- [ ] **Step 4: 运行驱动与全量测试并确认 GREEN**

Run: `swift test --filter MusicAccessibilityDriverTests && swift test`

Expected: 全部通过，无现有测试回归。

- [ ] **Step 5: 提交**

```bash
git add Sources/MusicAccessibilityDriver/MusicAccessibilityDriver.swift Tests/MusicAccessibilityDriverTests/MusicAccessibilityDriverTests.swift
git commit -m "feat: add exact Music search fallback"
```

### Task 4: 分发 Skill、文档与契约同步

**Files:**
- Modify: `skill/apple-music-playlist/SKILL.md`
- Modify: `README.md`
- Modify: `Tests/SkillPackageTests/package-contract.sh`
- Sync: `skill/apple-music-playlist/assets/helper/Sources/**`

**Interfaces:**
- Consumes: Task 3 的精确搜索回退。
- Produces: 自包含、中文说明准确的可安装 Skill。

- [ ] **Step 1: 写 Skill 契约失败检查**

在 `package-contract.sh` 中断言：Skill 明确禁止截图、OCR、固定坐标和相似版本替换；同时明确说明直接 URL 失败时只允许目录 ID 双重校验的搜索回退。

- [ ] **Step 2: 运行契约测试并确认 RED**

Run: `zsh Tests/SkillPackageTests/package-contract.sh`

Expected: 因 Skill 尚未描述精确搜索回退而退出非零。

- [ ] **Step 3: 更新中文文档并同步源码**

更新 `SKILL.md` 的执行、安全边界和错误处理；更新 `README.md` 的能力与限制。运行 `scripts/sync-skill-helper.sh`，把顶层 Package 源码同步到分发资产，不手工复制单个文件。

- [ ] **Step 4: 运行 Skill 契约和源码一致性检查**

Run: `for test in Tests/SkillPackageTests/*.sh; do zsh "$test"; done`

Run: `diff -ru Sources skill/apple-music-playlist/assets/helper/Sources`

Expected: 5 个契约脚本全部退出 `0`；`diff` 无输出。

- [ ] **Step 5: 提交**

```bash
git add README.md skill/apple-music-playlist Tests/SkillPackageTests/package-contract.sh
git commit -m "docs: publish exact search fallback workflow"
```

### Task 5: 发布验证与真实 Music 验收

**Files:**
- Create: `docs/superpowers/reports/2026-08-05-apple-music-exact-search-fallback-acceptance.md`
- Modify: `.superpowers/sdd/2026-08-05-apple-music-safe-removal-implementation/task-5-report.md`（本机执行记录，若被 Git 忽略则不提交）

**Interfaces:**
- Consumes: 完整仓库与分发 Skill。
- Produces: 第一版发布证据和准确剩余风险。

- [ ] **Step 1: 运行完整自动化验证**

Run: `swift test`

Run: `swift build -c release`

Run: `for test in Tests/SkillPackageTests/*.sh; do zsh "$test"; done`

Run: `npx --yes skills-ref validate skill/apple-music-playlist`

Run: `git diff --check`

Expected: Swift 测试零失败、Release 构建成功、5 个脚本退出 `0`、`Valid skill`、diff 检查无输出。

- [ ] **Step 2: 验证可移植安装**

用 `mktemp -d` 创建私有临时目录，把 Skill 安装到全新路径，运行 `bootstrap.sh --print-binary` 并确认 Release 二进制生成。检查包中没有 `/Users/macmini`、凭据模式、删除 token、`.build` 或预编译二进制，随后只删除这个已确认的临时安装目录。

- [ ] **Step 3: 执行真实 Music 新增验收**

创建名称为 `Apple Music Skill 测试 2026-08-05` 的临时播放列表；选择当前 storefront 可用且该列表中不存在的一首曲目。依次要求 dry-run `addable`、实际运行 `added`、写后回读曲名与艺人存在、第二次运行 `skipped_duplicate` 且数量不变。测试列表保留，不执行删除。

- [ ] **Step 4: 更新中文执行报告**

记录自动测试数、构建、技能验证、全新路径安装、真实 Music 首次新增与幂等结果，以及测试播放列表名称。不得记录凭据、删除 token 或完整私人资料库。

- [ ] **Step 5: 最终验证与提交**

Run: `git status --short && git diff --check && swift test`

Expected: 只有预期报告变化；diff 检查通过；Swift 测试零失败。

```bash
git add docs/superpowers/reports/2026-08-05-apple-music-exact-search-fallback-acceptance.md
git commit -m "docs: record exact search fallback acceptance"
```
