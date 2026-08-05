# Task 2：删除工作流报告

## 完成内容

- 新增 `RemovalWorkflow`：仅读取目标播放列表，在数据库 ID、曲名、艺人三项都精确匹配且唯一时才调用删除。
- `--dry-run` 仅生成“将删除”的 `removed` 结果，不调用 `MusicAppClient.remove`。
- 实际删除后立刻重新读取同一播放列表；仅当该数据库 ID 不再存在时报告 `removed`，否则报告 `verification_failed`。
- 缺失或歧义匹配、权限不足、读取失败和单项删除失败均不会误删；单项失败不会阻止后续项目。
- 删除输入补全 `databaseId`、`name`、`artist` 三项字段，并拒绝非 ASCII 数字数据库 ID 与空曲名、空艺人。
- `WorkflowReport.exitCode` 已将 `removed` 视为成功；文本渲染会显示中文“已删除”和删除项的曲名、艺人。
- `MusicAppClient` 新增删除契约；尚未实现的客户端默认安全失败，不会执行删除。原添加工作流假客户端已实现该契约。

## TDD 记录

### RED：删除工作流

命令：

```sh
swift test --filter RemovalWorkflowTests
```

结果：失败，符合预期。编译器报告 `RemovalTrack` 不接受曲名和艺人参数、`RemovalWorkflow` 不存在、`removed` 状态不存在；证明新增测试先于生产实现运行。

### GREEN：删除工作流

命令：

```sh
swift test --filter RemovalWorkflowTests
```

结果：通过，5 个测试、0 个失败。覆盖 dry-run 不写入、三项精确匹配、缺失/歧义不写入、写后复核失败和单项失败继续处理。

### RED：JSON 三字段契约

命令：

```sh
swift test --filter RemovalWorkflowTests/testInputDocumentDecodesThreeExactFieldsUsingDatabaseId
```

结果：失败，`DecodingError.keyNotFound` 指出旧模型只查找 `databaseID`，不能读取输入规范要求的 `databaseId`。

### GREEN：JSON 三字段契约

命令：

```sh
swift test --filter RemovalWorkflowTests
```

结果：通过，6 个测试、0 个失败。

### 最终验证

命令：

```sh
swift test && git diff --check
```

结果：通过。Swift 全量 50 个测试、0 个失败；差异检查无输出。

## 修改文件

- `Sources/PlaylistCore/RemovalWorkflow.swift`
- `Sources/PlaylistCore/Models.swift`
- `Sources/PlaylistCore/MusicAppClient.swift`
- `Sources/AMPlaylistCLIKit/ResultRendering.swift`
- `Tests/PlaylistCoreTests/RemovalWorkflowTests.swift`
- `Tests/PlaylistCoreTests/PlaylistWorkflowTests.swift`

## 提交

- `73f6ec1b18abf3670c20ce4ee1ead15fb289d2c3 feat: add safe playlist removal workflow`

## 风险与后续边界

- Task 3 尚未提供实际 JXA 删除实现；当前真实 `MusicAccessibilityDriver` 会安全失败，绝不会退化为资料库文件删除。
- 当前任务不保存“用户已在当前会话批准”或“已完成 dry-run”的会话状态；该人工授权与命令入口的强制规则由 Task 4 技能包装实现。核心工作流仍保持无模糊匹配、无跨列表参数、无重排和无整表删除入口。
- Task 3 必须让播放列表快照的数据库 ID 与 JSON `databaseId` 契约一致，并继续把 JXA 操作限定在指定用户播放列表的唯一曲目引用。

## 审查修复第 1 轮

### 修复内容

- 新增独立的 `RemovalWorkflowOptions` 与 `RemovalApproval`，不改变添加流程的 `WorkflowOptions`。
- dry-run 对“解析后的播放列表名 + 有序删除项三字段”生成 SHA-256 确认指纹，并通过 `WorkflowReport.removalConfirmationFingerprint` 返回。
- 非 dry-run 必须同时提供 `approved: true` 与完全相同的确认指纹；缺少批准、缺少指纹或指纹不一致均返回中文失败结果且零写入。
- 新增 `would_remove` 机器状态；dry-run 文本渲染为中文“将删除”，不会伪称“已删除”。该状态视为成功退出。
- 已提交删除但写后读取异常统一返回 `verification_failed`，并使快照失去可信性；下一项必须先重新读取成功才允许继续删除，重读失败时零写入。

### TDD 记录

#### RED

命令：

```sh
swift test --filter RemovalWorkflowTests
```

结果：失败，符合预期。新增渲染测试首先报告 `TrackOperationStatus` 缺少 `wouldRemove`，证明安全门、确认指纹和试运行状态的测试先于实现编译运行。

#### GREEN

命令：

```sh
swift test --filter RemovalWorkflowTests
swift test --filter ResultRenderingTests
```

结果：通过。删除工作流 8 个测试、渲染 3 个测试，均为 0 个失败；覆盖无批准/无指纹/错指纹零写入、正确指纹写入、复核读取异常后恢复可信快照再写入和 `would_remove` 中文渲染。

#### 最终验证

命令：

```sh
swift test && git diff --check
```

结果：通过。Swift 全量 53 个测试、0 个失败；差异检查无输出。

### 提交

- `9860f573f26ab62a11ad241e9a8a17b7b1b64a50 fix: require approved removal fingerprint`

### 更新后的关注点

- Task 4 的 CLI 分流必须显式传入 `RemovalWorkflowOptions`；真正执行前只能接受当前 dry-run 回传的原样指纹和明确批准，不能自行生成或替换指纹。
- Task 3 仍负责真实 JXA 删除；在它完成前，默认驱动保持安全失败。

## 审查修复第 2 轮

### 修复内容

- 删除了可自行计算确认指纹作为授权凭据的机制，改为一次性 `removalReceiptToken`。
- 新增 `RemovalReceiptStore` 协议、收据工件和内存收据存储。内存存储通过 `SecRandomCopyBytes` 生成 32 字节随机 token，并在 actor 内原子比对、消费，禁止重放。
- dry-run 将播放列表名、完整有序删除清单、完整播放列表快照 SHA-256 指纹、每项精确匹配结果与实际 `would_remove` 集合保存为收据工件，仅返回随机 token。
- 实际删除要求 `approved: true`、尚未消费的 token 和完全相同的当前工件。收据缺失、伪造、已消费、播放列表任意变化，或缺失/歧义结果后来变为唯一时均零写入并要求重新试运行。
- 保留上一轮 `would_remove` 中文渲染与写后复核异常后的可信快照恢复逻辑。

### TDD 记录

#### RED

命令：

```sh
swift test --filter RemovalWorkflowTests
```

结果：失败，符合预期。测试编译报告缺少 `RemovalReceiptStore`、`RemovalReceiptArtifact`、`receiptStore:` 初始化参数和 `receiptToken:` 授权参数，证明收据安全契约先于实现建立。

#### GREEN

命令：

```sh
swift test --filter RemovalWorkflowTests
swift test --filter ResultRenderingTests
```

结果：通过。删除工作流 11 个测试、渲染 3 个测试，均为 0 个失败；覆盖无存储收据、伪造 token、未批准、重放、任意快照变化、缺失/歧义 dry-run 后变唯一和正确收据删除。

#### 最终验证

命令：

```sh
swift test && git diff --check
```

结果：通过。Swift 全量 56 个测试、0 个失败；差异检查无输出。

### 提交

- `447d6423ec5c465e0b38150630bddb386e4211c8 fix: require one-time removal receipts`

### 更新后的关注点

- Task 4 的文件收据存储必须以等价的原子“匹配后消费”语义持久化 token，且 token 不得出现在普通日志、错误输出或归档内容中。
- 仅获得 token 仍不足以删除：CLI 必须显式提供 `approved: true`，并在实际运行前保留当前快照工件的完全一致校验。
