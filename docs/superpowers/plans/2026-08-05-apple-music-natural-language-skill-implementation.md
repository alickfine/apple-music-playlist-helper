# Apple Music 自然语言通用技能实施计划

> **供代理执行者使用：** 必须使用 `superpowers:executing-plans` 逐项实施；技能行为采用 `superpowers:writing-skills` 的红—绿—重构，脚本和 Swift 变更采用 `superpowers:test-driven-development`。步骤使用复选框跟踪。

**目标：** 把现有 Apple Music 播放列表助手打包成可独立安装的自然语言 Skill，使任意符合条件的 macOS 用户能按当次请求指定或默认确定曲风、区域和任意数量曲目，并添加到当前“音乐”账号的播放列表。

**架构：** 仓库保留开发源码和自动测试，`skill/apple-music-playlist/` 是唯一分发目录。技能正文负责自然语言理解、目录搜索、一次确认和错误路由；可注入 shell 脚本负责 storefront 解析、首次构建和稳定调用；`assets/helper/` 携带无个人路径的 Swift 执行层源码。仓库脚本机械同步执行层，避免分发副本与已测试源码漂移。

**技术栈：** Codex Skills、Markdown/YAML、zsh、Swift 6.2、Swift Package Manager、Foundation、ApplicationServices、JXA、XCTest。

## 全局约束

- 所有文档和用户可见诊断默认使用中文；技能回复跟随用户当前会话语言。
- 技能不预设曲风、语言、年代、用途、商店区域或曲目数量。
- 不设置曲目数量上限；大量曲目可以分批，但不得截断、抽样或减少。
- storefront 优先级固定为：当前请求、链接、用户配置、macOS 系统区域、询问一次。
- 不把中国区、美国区或开发者区域写成通用默认值。
- 分发目录不得包含 `/Users/macmini`、账号数据、密钥、Cookie、令牌或预编译二进制。
- 不需要 Apple Developer Program，不下载依赖，不修改 shell 配置。
- 默认先试运行；当前请求明确“直接添加”时视为本批次一次写入授权。
- 不删除、移动、重排、下载或分享曲目。
- 本机验收不得改变现有“试音”播放列表的 58 首基线。

---

## 文件结构

```text
skill/apple-music-playlist/
  SKILL.md
  agents/openai.yaml
  scripts/bootstrap.sh
  scripts/default-storefront.sh
  scripts/invoke.sh
  references/input-schema.md
  assets/helper/Package.swift
  assets/helper/Sources/**
Tests/SkillPackageTests/
  package-contract.sh
  storefront-resolution.sh
  portable-bootstrap.sh
  invoke-routing.sh
skill-tests/
  scenarios.md
  baseline-results.md
  forward-results.md
scripts/sync-skill-helper.sh
docs/superpowers/specs/2026-08-05-apple-music-natural-language-skill-design.md
```

### 任务 1：建立无技能行为基线

**文件：**
- 创建：`skill-tests/scenarios.md`
- 创建：`skill-tests/baseline-results.md`

**接口：**
- 产出：六个固定场景 ID：`NL-01` 至 `NL-06`。
- 产出：每个场景的基线输出摘要与失败标签，供任务 6 使用同场景复测。

- [ ] **步骤 1：编写行为场景**

在 `skill-tests/scenarios.md` 中写入以下完整自然语言请求与通过条件：

```markdown
| ID | 请求 | 通过条件 |
|---|---|---|
| NL-01 | 把我列出的爵士、摇滚和粤语歌加入“收藏”，共 135 首，不要减少数量。 | 不限定曲风，不截断；先试运行并汇总 135 首。 |
| NL-02 | 把这些 Apple Music 链接加入“通勤”，区域按链接处理，直接添加。 | 保留各链接 storefront；不重复确认当前批次写入。 |
| NL-03 | 推荐一些适合晚餐的歌加入“晚餐”，我没有指定区域和数量。 | 不套用试音偏好；只询问数量；区域按配置或系统默认，无法确定才询问。 |
| NL-04 | 只检查这批歌哪些已在“健身”，不要修改。 | 只执行 dry-run；不得创建、添加或播放。 |
| NL-05 | 把这 20 首加入不存在的“新列表”。 | 先报告列表缺失；未获创建授权不得创建。 |
| NL-06 | 我在加拿大区，把同名歌曲加入“对比”。 | 只接受加拿大 storefront 的唯一目录 ID；模糊结果逐首报未解析。 |
```

- [ ] **步骤 2：运行无技能基线**

对每个场景启动不携带当前对话和目标技能内容的全新代理，只给场景请求。禁止其写入真实“音乐”App。记录它是否要求手写命令、固定中国区、固定 20 首、截断 135 首、重复确认或忽略只读要求。

- [ ] **步骤 3：确认基线至少暴露一个缺口**

运行人工评分：六个场景中至少一个出现上述失败标签，才证明新技能提供了可测增量；若全部自然满足，则把实际输出记录为“无缺口”，停止创建冗余技能并重新评估范围。

- [ ] **步骤 4：提交基线资料**

```bash
git add skill-tests/scenarios.md skill-tests/baseline-results.md
git commit -m "test: capture natural language skill baseline"
```

### 任务 2：初始化标准技能目录与包契约

**文件：**
- 创建：`skill/apple-music-playlist/SKILL.md`
- 创建：`skill/apple-music-playlist/agents/openai.yaml`
- 创建：`skill/apple-music-playlist/scripts/`
- 创建：`skill/apple-music-playlist/references/`
- 创建：`skill/apple-music-playlist/assets/`
- 创建：`Tests/SkillPackageTests/package-contract.sh`

**接口：**
- 产出：技能名 `apple-music-playlist`。
- 产出：分发根目录 `skill/apple-music-playlist`。

- [ ] **步骤 1：先写失败的包契约测试**

`package-contract.sh` 必须断言：存在 `SKILL.md` 和 `agents/openai.yaml`；frontmatter 只有 `name`、`description`；技能名为 `apple-music-playlist`；不存在 README、预编译 Mach-O、`/Users/macmini`、英文待办占位标记和敏感字段模式。

- [ ] **步骤 2：运行测试并确认失败**

运行：`zsh Tests/SkillPackageTests/package-contract.sh`

预期：因 `skill/apple-music-playlist/SKILL.md` 不存在而失败。

- [ ] **步骤 3：使用官方初始化脚本生成目录**

运行：

```bash
python3 /Users/macmini/.codex/skills/.system/skill-creator/scripts/init_skill.py \
  apple-music-playlist \
  --path skill \
  --resources scripts,references,assets \
  --interface 'display_name=Apple Music 播放列表' \
  --interface 'short_description=用自然语言查找、去重并添加 Apple Music 曲目' \
  --interface 'default_prompt=把我指定的歌曲加入 Apple Music 播放列表，先核对目录和重复项。'
```

初始化后立即删除模板中的所有占位说明，但先保留一个最小合法 `SKILL.md`，内容只声明技能名、触发描述和“实现中，禁止执行写入”，以便后续任务逐步替换。

- [ ] **步骤 4：运行契约测试**

运行：`zsh Tests/SkillPackageTests/package-contract.sh`

预期：结构检查通过，且无个人路径和预编译文件。

- [ ] **步骤 5：提交**

```bash
git add skill Tests/SkillPackageTests/package-contract.sh
git commit -m "feat: initialize portable Apple Music skill package"
```

### 任务 3：同步自包含 Swift 执行层

**文件：**
- 创建：`scripts/sync-skill-helper.sh`
- 创建：`skill/apple-music-playlist/assets/helper/Package.swift`
- 创建：`skill/apple-music-playlist/assets/helper/Sources/**`
- 创建：`Tests/SkillPackageTests/portable-bootstrap.sh`
- 创建：`skill/apple-music-playlist/scripts/bootstrap.sh`

**接口：**
- 产出：`scripts/sync-skill-helper.sh`，把仓库 `Sources/` 机械同步到技能资产。
- 产出：`bootstrap.sh [--print-binary]`，成功时构建或返回技能内部 Release 二进制路径。

- [ ] **步骤 1：写独立路径构建失败测试**

测试复制 `skill/apple-music-playlist` 到 `mktemp -d`，断开对仓库根目录的依赖，运行复制品的 `scripts/bootstrap.sh --print-binary`，断言返回路径位于复制品内且文件可执行；再扫描复制品不得包含原仓库绝对路径。

- [ ] **步骤 2：运行测试并确认失败**

运行：`zsh Tests/SkillPackageTests/portable-bootstrap.sh`

预期：因 `bootstrap.sh` 或 `assets/helper/Package.swift` 不存在而失败。

- [ ] **步骤 3：实现同步脚本与最小分发 Manifest**

同步脚本使用自身路径计算仓库根目录，清空并复制 `Sources/` 到 `assets/helper/Sources/`。分发 Manifest 只声明三个 library target 和 `am-playlist` executable target，不包含测试 target；平台保持 macOS 26，Swift tools version 保持 6.2。

- [ ] **步骤 4：实现首次构建脚本**

`bootstrap.sh` 使用 `${0:A:h:h}` 计算技能根目录；确认 `uname -s` 为 `Darwin`、`swift` 可执行；运行 `swift build -c release --package-path "$技能根目录/assets/helper"`；不得下载文件或写入技能目录之外。`--print-binary` 只在成功后输出绝对路径。

- [ ] **步骤 5：同步、运行独立构建测试和仓库测试**

```bash
zsh scripts/sync-skill-helper.sh
zsh Tests/SkillPackageTests/portable-bootstrap.sh
swift test
```

预期：复制后的技能能自行构建，现有 Swift 测试全部通过。

- [ ] **步骤 6：提交**

```bash
git add scripts/sync-skill-helper.sh skill/apple-music-playlist Tests/SkillPackageTests/portable-bootstrap.sh
git commit -m "feat: bundle portable Swift helper in skill"
```

### 任务 4：实现无固定区域的 storefront 解析

**文件：**
- 创建：`skill/apple-music-playlist/scripts/default-storefront.sh`
- 创建：`Tests/SkillPackageTests/storefront-resolution.sh`
- 创建：`skill/apple-music-playlist/references/input-schema.md`

**接口：**
- 产出：`default-storefront.sh [--explicit CODE] [--url URL]`。
- 读取：`APPLE_MUSIC_STOREFRONT`、`${XDG_CONFIG_HOME:-$HOME/.config}/apple-music-playlist/storefront`、`APPLE_LOCALE` 测试覆盖值或 macOS `AppleLocale`。
- 输出：成功时仅输出小写双字母 storefront；无法确定时退出码 `4` 且输出中文诊断到 stderr。

- [ ] **步骤 1：写优先级失败测试**

测试依次覆盖：显式 `ca` 高于 URL `us`；URL `/jp/` 高于配置 `gb`；环境默认 `de`；临时配置文件 `fr`；`APPLE_LOCALE=pt_BR` 得到 `br`；无任何来源退出 `4`。同时断言 `cn`、`us` 没有被无条件写入输出。

- [ ] **步骤 2：运行测试并确认失败**

运行：`zsh Tests/SkillPackageTests/storefront-resolution.sh`

预期：因脚本不存在而失败。

- [ ] **步骤 3：实现严格解析脚本**

只接受正则 `^[A-Za-z]{2}$`；URL 只从 `https://music.apple.com/<code>/` 的首段路径提取；配置文件只读一行；系统区域从 `AppleLocale` 的国家部分提取。任何无效高优先级来源应报告错误而非静默降级。

- [ ] **步骤 4：编写输入参考**

`input-schema.md` 说明目录 ID、曲名、艺人、URL 和 playlist JSON 字段，以及 storefront 优先级。示例分别使用 `ca`、`jp`、`br`，不得把某一区域描述成全局默认。

- [ ] **步骤 5：运行测试和契约检查**

```bash
zsh Tests/SkillPackageTests/storefront-resolution.sh
zsh Tests/SkillPackageTests/package-contract.sh
```

- [ ] **步骤 6：提交**

```bash
git add skill/apple-music-playlist/scripts/default-storefront.sh skill/apple-music-playlist/references/input-schema.md Tests/SkillPackageTests/storefront-resolution.sh
git commit -m "feat: resolve Apple Music storefront without fixed region"
```

### 任务 5：实现稳定调用与任意数量输入

**文件：**
- 创建：`skill/apple-music-playlist/scripts/invoke.sh`
- 创建：`Tests/SkillPackageTests/invoke-routing.sh`
- 修改：`Tests/PlaylistCoreTests/TrackValidationTests.swift`

**接口：**
- 产出：`invoke.sh add [am-playlist 参数]`，自动调用 `bootstrap.sh --print-binary` 后以原参数 `exec` 执行。
- 保证：不解析或限制曲目数量；输入 JSON 原样交给已验证 Swift 层。

- [ ] **步骤 1：写调用路由和大输入失败测试**

shell 测试在临时技能副本中注入假的可执行文件，断言 `invoke.sh` 保留含空格和中文的所有参数。Swift 测试构造并编码 135 个不同目录 ID 的 `TrackInputDocument`，解码后断言 `tracks.count == 135` 且首尾顺序不变。

- [ ] **步骤 2：运行测试并确认失败**

```bash
zsh Tests/SkillPackageTests/invoke-routing.sh
swift test --filter TrackValidationTests.testLargeInputRetainsEveryTrackInOrder
```

预期：shell 脚本不存在，Swift 测试在添加生产约束前先证明模型当前行为；若 Swift 测试直接通过，则保留它作为防回归契约，不添加无意义生产代码。

- [ ] **步骤 3：实现最小调用脚本**

只接受 `add` 子命令；其他子命令退出 `2` 并输出中文帮助。使用数组原样传参，不使用 `eval`，不读取账号信息，不设置数量上限。

- [ ] **步骤 4：运行目标测试与完整测试**

```bash
zsh Tests/SkillPackageTests/invoke-routing.sh
swift test
```

- [ ] **步骤 5：重新同步分发执行层并提交**

```bash
zsh scripts/sync-skill-helper.sh
git add skill/apple-music-playlist Tests/SkillPackageTests Tests/PlaylistCoreTests scripts/sync-skill-helper.sh
git commit -m "feat: invoke helper without track count limits"
```

### 任务 6：编写自然语言技能正文与元数据

**文件：**
- 修改：`skill/apple-music-playlist/SKILL.md`
- 修改：`skill/apple-music-playlist/agents/openai.yaml`
- 修改：`skill-tests/forward-results.md`

**接口：**
- 产出：description 覆盖 Apple Music、播放列表、歌曲推荐、曲目链接、添加、去重、试运行和播放等触发词。
- 消费：`scripts/default-storefront.sh`、`scripts/invoke.sh`、`references/input-schema.md`。

- [ ] **步骤 1：把任务 1 的基线场景作为失败契约**

整理六个场景的失败标签，确认最小技能正文必须纠正：固定曲风、固定区域、固定数量、手写 CLI、重复确认和只读误写。

- [ ] **步骤 2：编写不超过 500 行的 SKILL.md**

frontmatter 只含：

```yaml
---
name: apple-music-playlist
description: Use when a macOS user wants to find, recommend, check, deduplicate, add, create, or play songs in an Apple Music playlist using natural language, Apple Music links, catalog IDs, track names, artists, genres, moods, languages, eras, storefront regions, or an arbitrary-size song list.
---
```

正文使用命令式流程，明确：不预设曲风；显式清单数量即请求数量；推荐缺数量才询问；按 storefront 优先级解析；无匹配时失败关闭；默认 dry-run；明确直接添加不重复确认；大量曲目分批但不截断；只通过 `invoke.sh` 执行，不要求用户手写命令。

- [ ] **步骤 3：重新生成 UI 元数据**

运行官方 `generate_openai_yaml.py`，传入与技能正文一致的中文 `display_name`、`short_description` 和不带固定曲风/区域/数量的 `default_prompt`。

- [ ] **步骤 4：运行官方校验与包契约**

```bash
python3 /Users/macmini/.codex/skills/.system/skill-creator/scripts/quick_validate.py skill/apple-music-playlist
zsh Tests/SkillPackageTests/package-contract.sh
```

- [ ] **步骤 5：用相同场景进行技能前向复测**

对 `NL-01` 至 `NL-06` 各启动全新代理，只传目标技能路径和原始用户请求，禁止真实写入。记录每个输出到 `forward-results.md`；六项必须全部满足通过条件。发现新的固定偏好、截断或确认漏洞时，先把失败记录下来，再最小修改 `SKILL.md` 并复测。

- [ ] **步骤 6：提交**

```bash
git add skill/apple-music-playlist skill-tests/forward-results.md
git commit -m "feat: add universal Apple Music natural language workflow"
```

### 任务 7：验证独立安装与本机技能发现

**文件：**
- 修改：`README.md`
- 创建：`scripts/install-skill-local.sh`
- 修改：`Tests/SkillPackageTests/portable-bootstrap.sh`

**接口：**
- 产出：`install-skill-local.sh [目标技能根目录]`，默认目标为 `${CODEX_HOME:-$HOME/.codex}/skills`。
- 安装结果：`<目标技能根目录>/apple-music-playlist/SKILL.md`。

- [ ] **步骤 1：写临时根目录安装失败测试**

扩展 `portable-bootstrap.sh`：设置临时目标根目录，运行安装脚本，删除对仓库的引用后从安装副本执行官方 `quick_validate.py` 和 `bootstrap.sh --print-binary`；断言安装目录没有开发者路径、Git 元数据和预编译二进制初始包。

- [ ] **步骤 2：运行测试并确认失败**

运行：`zsh Tests/SkillPackageTests/portable-bootstrap.sh`

预期：因 `install-skill-local.sh` 不存在或安装副本不完整而失败。

- [ ] **步骤 3：实现无管理员权限安装脚本**

脚本只复制 `skill/apple-music-playlist` 到精确目标；目标已存在时先比较并使用临时同级目录原子替换，不删除其他技能，不修改 shell 配置，不构建二进制。

- [ ] **步骤 4：更新中文项目 README**

说明自然语言示例、支持任意曲风/区域/数量、默认区域优先级、安装、权限、一次确认、卸载和不支持平台。README 属于开发仓库，不复制进技能目录。

- [ ] **步骤 5：运行临时安装验收**

```bash
zsh Tests/SkillPackageTests/portable-bootstrap.sh
python3 /Users/macmini/.codex/skills/.system/skill-creator/scripts/quick_validate.py skill/apple-music-playlist
```

- [ ] **步骤 6：安装到本机全局技能目录并检查发现文件**

运行：`zsh scripts/install-skill-local.sh`。确认 `/Users/macmini/.codex/skills/apple-music-playlist/SKILL.md` 存在；不触发真实添加。新任务可能需要重启或重新加载技能列表，这是发现机制限制，不视为安装失败。

- [ ] **步骤 7：提交**

```bash
git add README.md scripts/install-skill-local.sh Tests/SkillPackageTests/portable-bootstrap.sh
git commit -m "docs: add portable skill installation and natural language usage"
```

### 任务 8：最终验证与只读验收

**文件：**
- 只在验证发现缺陷时修改对应生产文件和先行回归测试。

**接口：**
- 消费全部前置任务产物。

- [ ] **步骤 1：运行干净完整测试与发布构建**

```bash
swift package clean
swift test
swift build -c release
zsh Tests/SkillPackageTests/package-contract.sh
zsh Tests/SkillPackageTests/storefront-resolution.sh
zsh Tests/SkillPackageTests/invoke-routing.sh
zsh Tests/SkillPackageTests/portable-bootstrap.sh
python3 /Users/macmini/.codex/skills/.system/skill-creator/scripts/quick_validate.py skill/apple-music-playlist
```

- [ ] **步骤 2：运行通用性和安全扫描**

扫描分发目录：不得出现 `/Users/macmini`、固定 `cn`/`us` 默认赋值、`maxTracks`、`limit 20`、密钥模式、`.build`、Mach-O 或 Git 元数据；允许参考文档把 `ca`、`jp`、`br` 用作非默认示例。

- [ ] **步骤 3：执行真实只读验收**

读取“试音”曲目数，必须为 58；通过技能安装副本的 `invoke.sh` 对《被遗忘的时光》执行 `--dry-run --json`，预期 `skipped_duplicate`、退出码 `0`；再次读取仍为 58。不得为了验收创建或删除播放列表。

- [ ] **步骤 4：检查仓库状态与提交记录**

```bash
git diff --check
git status --short
git log --oneline --decorate -15
```

预期：工作树干净，所有技能与测试变更均已提交。
