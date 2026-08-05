# Task 4：CLI、技能包装与持久化收据报告

## 完成内容

- CLI 已按 `add` / `remove` 解码不同输入模型并分流到各自工作流。
- 删除试运行必须显式提供调用者创建的 `--receipt-dir`、`--dry-run --json`；实际删除必须提供同一收据目录、`--approved` 与原样 `--receipt-token`。
- 新增文件型 `FileRemovalReceiptStore`。收据工件写入调用者目录并设为 `0600`；64 位十六进制随机 token 不能形成路径逃逸。
- 文件收据可跨 CLI 进程读取。消费时先在同一目录原子 `rename` 抢占，再完整解码并比对工件；完全匹配才删除，工件不匹配则恢复，伪造、并发重放和已消费 token 均零写入。
- CLI 参数、文件/JSON 错误和收据目录错误均返回中文；未知参数错误不回显原值，避免意外记录 token。
- `invoke.sh` 只白名单 `add` / `remove`，移动、重排、分享、下载和资料库文件删除命令仍拒绝；分发包已同步完整删除工作流、精确 JXA 驱动和文件收据存储。
- `SKILL.md` 与中文输入规范要求：只删除当前会话明确批准的单列表三字段精确清单；先 dry-run，在同一临时目录原样传递 token，写后复核，最后清理临时目录；禁止模糊、整表、跨列表和资料库文件删除。
- 混合“删除 28 首、再新增 20 首”规则明确先删除后新增；任一删除安全门失败就停止新增，不能只新增到 78 首，也不能绕过 `invoke.sh` 或 JXA 驱动。

## TDD 记录

### RED

- `swift test --filter CLIOptionsTests`：按预期编译失败，报告 `CLIOptions` 缺少 `receiptDirectory`、`approved`、`receiptToken`。
- `swift test --filter FileRemovalReceiptStoreTests`：测试目标因文件收据类型/CLI 新接口尚不存在而失败。
- `zsh Tests/SkillPackageTests/invoke-routing.sh`：按预期退出 2，旧包装只接受 `add`。
- `zsh Tests/SkillPackageTests/package-contract.sh`：按预期报告分发执行层缺少文件型删除收据存储。
- `zsh Tests/SkillPackageTests/remove-command-rejection.sh`：旧 CLI 返回“remove 暂未实现”，不符合新的显式批准安全门。
- `swift test --filter RemovalWorkflowTests/testDryRunFailsClosedWhenReceiptCannotBePersisted`：按预期得到 `would_remove` 和空 token，而不是失败；证明收据写入失败必须显式关闭。

### GREEN

- `swift test --filter CLIOptionsTests`：12/12 通过。
- `swift test --filter FileRemovalReceiptStoreTests`：4/4 通过，覆盖跨实例持久化、工件不匹配不消费、并发仅一次消费和伪造 token 防路径逃逸。
- 全部 `Tests/SkillPackageTests/*.sh` 通过，含独立分发包 Release 构建。
- 收据无法持久化筛选测试：1/1 通过，返回中文失败、无 token、零写入。
- 全量 `swift test`：66/66 通过。

## 技能规则自检

新增 NL-07、NL-08 场景并记录旧技能基线。全新上下文代理只读加载更新后技能，自检结果：精确删除 28 首再新增 20 首时遵守同目录收据、原样 token、删除优先和失败停止新增；对“不喜欢、重复、跨列表清理”拒绝执行并要求单列表三字段精确清单。自检未操作真实“音乐”App，也未修改文件。

## 关注点

- 未对真实 Music.app 执行删除，以免开发验证触发不可逆写入；核心工作流、跨进程收据、CLI 参数门、包装路由和 JXA 目标边界由自动测试覆盖。
- token 按接口要求经命令行原样传递；技能必须在同一受控进程中捕获 dry-run JSON，不打印或持久记录 token，并在完成或失败后删除调用者临时目录。
- 文件收据存储不会自行创建全局目录；调用者必须显式传入已存在目录。目录不可用时 CLI 中文失败并零写入。

## 审查修复第 1 轮

### 修复内容

- 文件收据消费不再使用 `rename` 抢占和失败恢复。现在通过已验证目录描述符 `openat(O_NOFOLLOW)` 打开收据，使用 `flock(LOCK_EX | LOCK_NB)` 获取跨进程独占锁，在锁内读取并完整比较工件；只对同一路径、同一 inode 且链接数仍为 1 的完全匹配文件执行 `unlinkat`。工件不匹配保留原文件，并发、锁冲突、已消费和重放均失败关闭。
- 收据目录先以 `lstat` 拒绝符号链接，再用 `open(O_DIRECTORY | O_NOFOLLOW)` 与 `fstat` 防止打开时替换；只接受 `owner == geteuid()` 且 group/other 权限为 0 的目录。每次操作前重新检查目录权限，权限后来放宽也停止。
- 收据文件直接以 `openat(O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0600)` 创建，写入、`fsync` 和关闭任一步失败都会删除不完整文件；读取和消费还会复核普通文件、owner 和精确 `0600`。
- `remove` 必须通过命令行或输入 JSON 明确指定播放列表；缺失时返回中文参数错误。`add` 继续保留默认“试音”，未回归。
- 安全删除设计和实施计划已改为：先对 28 首 dry-run、实际删除并结构化核验；任一失败立即停止新增；全部通过后才 dry-run 并新增 20 首，避免只新增至 78 首。
- 顶层 README 已补齐中文 add/remove 能力、输入格式、一次性收据安全流程、全部参数和混合操作顺序；技能正文、输入规范和分发助手同步更新。

### TDD 与验证记录

#### RED

- 新增 CLI 测试后，`swift test --filter FileRemovalReceiptStoreTests` 首先因 `CLIOptionsError.missingRemovalPlaylist` 不存在而编译失败；证明 remove 显式播放列表契约先于实现。
- 目录运行期权限测试先得到非空 token 和已创建文件，明确暴露“初始化后目录权限放宽仍可写”的缺口。
- 对独占锁保护执行突变检查：暂时移除生产 `flock` 后，锁冲突测试错误返回已消费且原收据消失，2 个断言按预期失败；恢复锁后重新通过。

#### GREEN

- `swift test --filter CLIOptionsTests`：14/14 通过。
- `swift test --filter FileRemovalReceiptStoreTests`：9/9 通过，覆盖目录 symlink、group/other 权限、owner 边界、运行期权限变化、文件 `0600`、工件不匹配保留、锁冲突保留、并发仅一次消费和伪造 token。
- `swift test`：73/73 通过。
- 全部 `Tests/SkillPackageTests/*.sh` 通过，独立技能 Release 构建成功。
- 分发源码与顶层 `Sources` 无差异；全部相关 zsh 脚本语法检查和 `git diff --check` 通过。
