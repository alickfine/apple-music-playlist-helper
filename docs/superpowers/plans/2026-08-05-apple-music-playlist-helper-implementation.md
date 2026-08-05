# Apple Music 播放列表助手实施计划

> **供代理执行者使用：** 必须按任务逐项执行，并使用 `superpowers:executing-plans`；每个功能严格遵守红—绿—重构。步骤使用复选框跟踪。

**目标：** 构建一个不依赖截图和 Apple Developer Program 的本机 Swift 命令行助手，通过“音乐”App 的脚本字典与辅助功能树，把准确的 Apple Music 目录曲目加入指定播放列表，并完成去重和验证。

**架构：** `PlaylistCore` 负责纯业务模型、输入校验、规范化和工作流；`MusicAccessibilityDriver` 负责只读清单、URL 导航和准确辅助功能元素操作；`AMPlaylistCLIKit` 负责命令行解析与输出；`am-playlist` 可执行目标只负责装配依赖。真实驱动均通过协议注入，自动化测试不启动“音乐”App。

**技术栈：** Swift 6.3、Swift Package Manager、Foundation、ApplicationServices/AXUIElement、XCTest、AppleScript/JXA、macOS 26 SDK。

## 全局约束

- 所有文档和用户可见诊断默认使用中文；命令、代码标识符和状态枚举保持英文。
- 目标平台为 macOS 26，Swift 工具链最低使用本机 Swift 6.3。
- 不引入第三方 Swift 依赖，不需要网络安装步骤。
- 不使用截图、OCR、固定屏幕坐标或近似曲名点击。
- 未传入 `--create` 时不得创建播放列表。
- 不删除、移动、重排、下载、分享或修改现有曲目。
- 每个生产函数必须先有能够正确失败的测试。
- 集成验收不得改变现有“试音”播放列表的 58 首基线。

---

## 文件结构

```text
Package.swift
Sources/
  PlaylistCore/
    Models.swift
    TrackValidation.swift
    TextNormalization.swift
    MusicAppClient.swift
    PlaylistWorkflow.swift
  MusicAccessibilityDriver/
    ProcessRunner.swift
    MusicScriptReader.swift
    AccessibilityTree.swift
    AccessibilityMatching.swift
    MusicAccessibilityDriver.swift
  AMPlaylistCLIKit/
    CLIOptions.swift
    ResultRendering.swift
  am-playlist/
    main.swift
Tests/
  PlaylistCoreTests/
    TrackValidationTests.swift
    TextNormalizationTests.swift
    PlaylistWorkflowTests.swift
  MusicAccessibilityDriverTests/
    MusicScriptReaderTests.swift
    AccessibilityMatchingTests.swift
  AMPlaylistCLIKitTests/
    CLIOptionsTests.swift
    ResultRenderingTests.swift
Fixtures/
  tracks.example.json
scripts/
  install-local.sh
README.md
```

### 任务 1：建立 Swift Package 与输入模型

**文件：**
- 创建：`Package.swift`
- 创建：`Sources/PlaylistCore/Models.swift`
- 创建：`Sources/PlaylistCore/TrackValidation.swift`
- 创建：`Tests/PlaylistCoreTests/TrackValidationTests.swift`

**接口：**
- 产出：`CatalogTrack`、`TrackInputDocument`、`TrackValidationError`。
- 产出：`CatalogTrack.validated() throws -> CatalogTrack`。

- [ ] **步骤 1：写输入校验失败测试**

测试必须覆盖有效国区 URL、非数字 ID、非 HTTPS、错误主机、缺少 `i` 参数、`i` 与 `id` 不一致、空曲名和空艺人。示例：

```swift
func testRejectsMismatchedCatalogID() throws {
    let track = CatalogTrack(
        id: "905228611",
        name: "被遗忘的时光",
        artist: "蔡琴",
        url: URL(string: "https://music.apple.com/cn/album/example/1?i=123")!
    )
    XCTAssertThrowsError(try track.validated()) { error in
        XCTAssertEqual(error as? TrackValidationError, .catalogIDMismatch)
    }
}
```

- [ ] **步骤 2：运行测试并确认因类型不存在而失败**

运行：`swift test --filter TrackValidationTests`

预期：编译失败，错误指向 `CatalogTrack` 或 `TrackValidationError` 尚未定义。

- [ ] **步骤 3：编写最小模型与校验实现**

`CatalogTrack` 遵循 `Codable`、`Equatable`、`Sendable`；`validated()` 使用 `URLComponents`，要求 scheme 为 `https`、host 为 `music.apple.com`、目录 ID 仅包含数字，且唯一 `i` 参数与 `id` 一致。

- [ ] **步骤 4：运行目标测试与完整测试**

运行：`swift test --filter TrackValidationTests && swift test`

预期：全部通过且无警告。

- [ ] **步骤 5：提交**

```bash
git add Package.swift Sources/PlaylistCore Tests/PlaylistCoreTests
git commit -m "feat: add validated catalog track input"
```

### 任务 2：实现文本规范化、去重和结果模型

**文件：**
- 创建：`Sources/PlaylistCore/TextNormalization.swift`
- 修改：`Sources/PlaylistCore/Models.swift`
- 创建：`Tests/PlaylistCoreTests/TextNormalizationTests.swift`

**接口：**
- 产出：`TrackKey.init(name:artist:)`，属性为规范化后的 `name`、`artist`。
- 产出：`TrackOperationStatus`：`added`、`skippedDuplicate`、`notFound`、`permissionDenied`、`playlistMissing`、`verificationFailed`、`failed`。
- 产出：`TrackOperationResult` 与 `WorkflowReport.exitCode`。

- [ ] **步骤 1：写规范化与退出码失败测试**

测试组合/分解 Unicode、全角与半角空白、重复空白、大小写、中文/ASCII 常见标点；确认同曲名不同艺人不会被去重；确认任意后置失败状态映射为退出码 `5`。

- [ ] **步骤 2：运行测试并确认失败原因正确**

运行：`swift test --filter TextNormalizationTests`

预期：因 `TrackKey` 和结果类型尚未定义而失败。

- [ ] **步骤 3：编写最小规范化与结果实现**

规范化顺序固定为：兼容分解映射、按 Unicode 空白折叠、`localizedLowercase`、去除集合 `，。！？、；：,.!?;:'\"“”‘’（）()【】[]` 中的标点、再次折叠空白。

- [ ] **步骤 4：运行目标测试与完整测试**

运行：`swift test --filter TextNormalizationTests && swift test`

- [ ] **步骤 5：提交**

```bash
git add Sources/PlaylistCore Tests/PlaylistCoreTests
git commit -m "feat: add track deduplication keys and result model"
```

### 任务 3：实现可测试的播放列表工作流

**文件：**
- 创建：`Sources/PlaylistCore/MusicAppClient.swift`
- 创建：`Sources/PlaylistCore/PlaylistWorkflow.swift`
- 创建：`Tests/PlaylistCoreTests/PlaylistWorkflowTests.swift`

**接口：**
- 产出协议：

```swift
public protocol MusicAppClient: Sendable {
    func accessibilityAuthorized() async -> Bool
    func playlist(named: String) async throws -> PlaylistSnapshot?
    func createPlaylist(named: String) async throws
    func add(_ track: CatalogTrack, to playlist: String, timeout: Duration) async throws -> AddTrackOutcome
    func play(track: CatalogTrack, in playlist: String) async throws
}
```

- 产出：`PlaylistWorkflow.run(document:options:) async -> WorkflowReport`。
- 消费：任务 1、2 的模型与 `TrackKey`。

- [ ] **步骤 1：写工作流失败测试**

使用记录调用次数的 `FakeMusicAppClient` 覆盖：无权限时不读取播放列表；播放列表缺失且无 `--create` 时不创建；`--create` 只创建一次；`--dry-run` 不调用写入；重复项跳过；单首失败后继续；写入后重新读取并验证；`--play-first` 只调用一次播放。

- [ ] **步骤 2：运行测试并确认因工作流不存在而失败**

运行：`swift test --filter PlaylistWorkflowTests`

- [ ] **步骤 3：编写最小协议与工作流实现**

工作流按输入顺序生成结果。`add` 返回成功后必须再次调用 `playlist(named:)`，只有新快照包含目标 `TrackKey` 才返回 `added`，否则返回 `verificationFailed`。

- [ ] **步骤 4：运行目标测试与完整测试**

运行：`swift test --filter PlaylistWorkflowTests && swift test`

- [ ] **步骤 5：提交**

```bash
git add Sources/PlaylistCore Tests/PlaylistCoreTests
git commit -m "feat: orchestrate safe playlist additions"
```

### 任务 4：实现只读 Music 清单适配器

**文件：**
- 创建：`Sources/MusicAccessibilityDriver/ProcessRunner.swift`
- 创建：`Sources/MusicAccessibilityDriver/MusicScriptReader.swift`
- 创建：`Tests/MusicAccessibilityDriverTests/MusicScriptReaderTests.swift`

**接口：**
- 产出：

```swift
public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data
}

public protocol ProcessRunning: Sendable {
    func run(executable: URL, arguments: [String], stdin: Data?) async throws -> ProcessResult
}
```

- 产出：`ProcessRunner.run(executable:arguments:stdin:) async throws -> ProcessResult`。
- 产出：`MusicScriptReader.playlist(named:) async throws -> PlaylistSnapshot?`。
- 产出：`MusicScriptReader.createPlaylist(named:)` 和 `play(track:in:)`，调用前由上层权限与参数规则约束。

- [ ] **步骤 1：写进程与 JSON 解析失败测试**

注入假的 `ProcessRunning`，测试合法 JXA JSON、播放列表不存在、曲目字段缺失、非零退出码和 stderr 中文诊断映射。

- [ ] **步骤 2：运行测试并确认失败原因正确**

运行：`swift test --filter MusicScriptReaderTests`

- [ ] **步骤 3：实现最小 Process 与 JXA 适配器**

只读 JXA 输出以下 JSON，不输出其他资料库内容：

```json
{"name":"试音","tracks":[{"name":"被遗忘的时光","artist":"蔡琴"}]}
```

创建播放列表使用准确名称；播放功能只在目标播放列表中按规范化后的 `(name, artist)` 唯一匹配，否则失败。

- [ ] **步骤 4：运行目标测试与完整测试**

运行：`swift test --filter MusicScriptReaderTests && swift test`

- [ ] **步骤 5：提交**

```bash
git add Sources/MusicAccessibilityDriver Tests/MusicAccessibilityDriverTests
git commit -m "feat: read and control Music playlists through scripts"
```

### 任务 5：实现辅助功能树准确匹配与生产驱动

**文件：**
- 创建：`Sources/MusicAccessibilityDriver/AccessibilityTree.swift`
- 创建：`Sources/MusicAccessibilityDriver/AccessibilityMatching.swift`
- 创建：`Sources/MusicAccessibilityDriver/MusicAccessibilityDriver.swift`
- 创建：`Tests/MusicAccessibilityDriverTests/AccessibilityMatchingTests.swift`

**接口：**
- 产出：`AccessibilityNodeSnapshot`，包含 `identifier`、`role`、`title`、`description`、`children`。
- 产出：`AccessibilityMatcher.trackMoreButton(catalogID:in:) -> AccessibilityPath?`。
- 产出：`AccessibilityMatcher.playlistMenuItem(named:in:) -> AccessibilityPath?`。
- 产出：实现 `MusicAppClient` 的 `MusicAccessibilityDriver`。
- 产出以下可注入边界：

```swift
public protocol AccessibilityProviding: Sendable {
    func isAuthorized() -> Bool
    func musicTree() throws -> AccessibilityNodeSnapshot
    func press(path: AccessibilityPath) throws
}

public protocol URLOpening: Sendable {
    func openInMusic(_ url: URL) async throws
}
```

轮询等待使用 Swift 标准库的 `Clock` 泛型注入，不定义第二套时钟协议。

- [ ] **步骤 1：写 fixture 匹配失败测试**

fixture 同时包含近似曲名、多个“更多”按钮、目录 ID `905228611` 和 `905228612`。断言只返回准确 ID 所属行的“更多”路径；准确 ID 不存在时返回 `nil`；播放列表名称必须完全一致。

- [ ] **步骤 2：运行测试并确认失败原因正确**

运行：`swift test --filter AccessibilityMatchingTests`

- [ ] **步骤 3：实现纯匹配器**

匹配器不接触系统 API，只遍历不可变 snapshot。目录行标识符必须包含正则边界意义上的完整数字 ID，不能使用模糊子串匹配。

- [ ] **步骤 4：运行匹配测试并确认通过**

运行：`swift test --filter AccessibilityMatchingTests`

- [ ] **步骤 5：写生产驱动失败测试**

通过注入 `AccessibilityProviding`、`URLOpening` 和 `Clock`，测试：打开准确 URL；轮询至目标出现；超时返回 `.notFound`；目标菜单不存在时不执行第二次按压；写入按压顺序固定为曲目“更多”后目标播放列表。

- [ ] **步骤 6：实现 AXUIElement 生产适配器**

使用 `AXIsProcessTrusted()` 做无提示权限检查；使用 `/usr/bin/open -a Music <url>` 导航；从 Music 进程根元素读取 `kAXChildrenAttribute`、`kAXIdentifierAttribute`、`kAXRoleAttribute`、`kAXTitleAttribute`、`kAXDescriptionAttribute`；只对已由 matcher 选中的元素执行 `kAXPressAction`。

- [ ] **步骤 7：运行目标测试与完整测试**

运行：`swift test --filter MusicAccessibilityDriverTests && swift test`

- [ ] **步骤 8：提交**

```bash
git add Sources/MusicAccessibilityDriver Tests/MusicAccessibilityDriverTests
git commit -m "feat: add exact Music accessibility driver"
```

### 任务 6：实现中文 CLI 与结果输出

**文件：**
- 创建：`Sources/AMPlaylistCLIKit/CLIOptions.swift`
- 创建：`Sources/AMPlaylistCLIKit/ResultRendering.swift`
- 创建：`Sources/am-playlist/main.swift`
- 创建：`Tests/AMPlaylistCLIKitTests/CLIOptionsTests.swift`
- 创建：`Tests/AMPlaylistCLIKitTests/ResultRenderingTests.swift`

**接口：**
- 产出：`CLIOptions.parse(_:) throws -> CLIOptions`。
- 产出：`ResultRenderer.render(report:json:) throws -> String`。
- 消费：`PlaylistWorkflow` 与 `MusicAccessibilityDriver`。

- [ ] **步骤 1：写参数解析失败测试**

覆盖缺少子命令、缺少输入、冲突的播放列表来源、`--timeout` 非正数、未知参数、全部可选参数和默认 8 秒。

- [ ] **步骤 2：运行参数测试并确认失败**

运行：`swift test --filter CLIOptionsTests`

- [ ] **步骤 3：实现最小参数解析器**

不引入第三方依赖。支持且只支持规格中列出的 `add`、`--playlist`、`--input`、`--create`、`--dry-run`、`--play-first`、`--timeout`、`--json`。

- [ ] **步骤 4：写中文与 JSON 输出失败测试**

断言文本模式逐首输出中文状态，JSON 模式状态值保持机器枚举；任何输出不得包含未请求的资料库曲目。

- [ ] **步骤 5：实现结果渲染与可执行入口**

入口读取 UTF-8 JSON、装配真实驱动、运行工作流、写 stdout/stderr，并使用 `WorkflowReport.exitCode` 退出。

- [ ] **步骤 6：运行 CLI 目标测试与完整测试**

运行：`swift test --filter AMPlaylistCLIKitTests && swift test`

- [ ] **步骤 7：提交**

```bash
git add Sources/AMPlaylistCLIKit Sources/am-playlist Tests/AMPlaylistCLIKitTests
git commit -m "feat: add Chinese am-playlist command line interface"
```

### 任务 7：中文文档、示例、安装与非写入验收

**文件：**
- 创建：`README.md`
- 创建：`Fixtures/tracks.example.json`
- 创建：`scripts/install-local.sh`
- 修改：`Package.swift`

**接口：**
- 产出：`swift run am-playlist add ...` 和安装后的 `am-playlist add ...`。

- [ ] **步骤 1：写安装脚本行为测试命令**

在临时目录运行构建与安装路径检查，不写入系统目录：

```bash
swift build -c release
test -x .build/release/am-playlist
```

- [ ] **步骤 2：编写中文 README 与示例**

README 必须包含：用途、权限最小化、安装、输入格式、全部参数、退出码、`--dry-run`、常见错误、卸载方式和“不会执行的操作”。示例使用国区可搜索但不会在文档命令中自动写入的曲目数据。

- [ ] **步骤 3：编写无管理员权限安装脚本**

脚本接收可选目标目录，默认安装到 `${HOME}/.local/bin`；只复制当前项目构建出的 `am-playlist`，不得下载文件或修改 shell 配置。

- [ ] **步骤 4：运行完整静态与自动测试**

运行：

```bash
swift test
swift build -c release
git diff --check
rg -n "待补充|稍后实现|占位内容" README.md docs Sources Tests scripts
```

预期：测试与构建成功，`git diff --check` 无输出，占位符扫描无命中。

- [ ] **步骤 5：运行真实非写入验收**

先读取“试音”基线，必须为 58 首。创建只含《被遗忘的时光》—蔡琴的临时输入文件，运行：

```bash
swift run am-playlist add --playlist "试音" --input /tmp/am-playlist-acceptance.json --dry-run --json
```

预期：返回 `skipped_duplicate`、退出码 `0`；再次读取“试音”仍为 58 首。若缺少辅助功能权限，验收结果必须是退出码 `3` 和准确中文授权路径，不得改动播放列表。

- [ ] **步骤 6：提交**

```bash
git add README.md Fixtures scripts Package.swift
git commit -m "docs: add Chinese usage and local installation"
```

### 任务 8：最终验证与交付

**文件：**
- 仅在验证发现缺陷时修改对应生产文件和其测试；每个缺陷先写回归测试。

**接口：**
- 消费全部前置任务产物。

- [ ] **步骤 1：运行干净的完整测试与发布构建**

```bash
swift package clean
swift test
swift build -c release
```

- [ ] **步骤 2：运行项目状态检查**

```bash
git diff --check
git status --short
```

- [ ] **步骤 3：再次执行“试音”只读验收**

确认报告为 `skipped_duplicate`，退出码为 `0`，歌单仍为 58 首。不得为了通过验收而写入或删除任何曲目。

- [ ] **步骤 4：记录验证证据并提交剩余必要变更**

只有存在由测试证明的必要修复时才创建提交；否则保持工作树干净。
