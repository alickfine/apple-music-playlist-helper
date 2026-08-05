# Apple Music 播放列表助手首次公开发布实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把已完成的 Apple Music 本机自然语言 Skill 作为公开 GitHub 第一版发布，并把项目知识归档到 AlickFine Obsidian。

**Architecture:** 发布只增加许可证、README 安装入口和发布文档，不改变执行层。GitHub 使用现有 Git 历史首次创建公开远程；Obsidian 使用单一规范概览与归档清单记录脱敏知识。

**Tech Stack:** Git、GitHub CLI、Swift Package Manager、Codex Skill、Markdown、Obsidian

## Global Constraints

- 公开仓库名称固定为 `alickfine/apple-music-playlist-helper`。
- 许可证固定为 MIT，版权标识为 `AlickFine`。
- 不修改 Swift 源码、Skill 行为或 Apple Music 数据。
- 文档使用中文，机器标识、命令、文件名和产品名保留英文。
- 不发布凭据、本机账号信息、构建产物、缓存或运行日志。

---

### Task 1: 补齐公开发布元数据

**Files:**
- Create: `LICENSE`
- Modify: `README.md`

**Interfaces:**
- Consumes: 现有 `scripts/install-skill-local.sh` 和 `skill/apple-music-playlist/` 分发目录。
- Produces: 可从 GitHub 克隆并安装的公开入口与明确再分发许可。

- [ ] **Step 1: 创建 MIT 许可证**

写入标准 MIT 文本，版权行为 `Copyright (c) 2026 AlickFine`。

- [ ] **Step 2: 增加 GitHub 快速安装段落**

在 README 的“自然语言 Skill”部分增加：

```bash
git clone https://github.com/alickfine/apple-music-playlist-helper.git
cd apple-music-playlist-helper
./scripts/install-skill-local.sh
```

- [ ] **Step 3: 检查发布元数据**

Run: `git diff --check && rg -n 'MIT License|git clone https://github.com/alickfine/apple-music-playlist-helper.git' LICENSE README.md`

Expected: 退出码 0，许可证和克隆命令各有精确匹配。

### Task 2: 验证并发布 GitHub 第一版

**Files:**
- Modify: Git index and repository remote configuration

**Interfaces:**
- Consumes: Task 1 的发布元数据与现有测试套件。
- Produces: `https://github.com/alickfine/apple-music-playlist-helper` 公共仓库。

- [ ] **Step 1: 运行完整验证**

Run:

```bash
swift test
swift build -c release
for test_script in Tests/SkillPackageTests/*.sh; do zsh "$test_script"; done
```

Expected: Swift 测试 0 失败、Release 构建成功、五个 Skill 包测试全部退出 0。

- [ ] **Step 2: 运行公开内容审计**

Run: `git status -sb && git diff --check && git ls-files | rg '(^|/)\.build/' && exit 1 || true`

Expected: 只有本次发布文件发生变化，未跟踪任何 `.build` 文件。

- [ ] **Step 3: 提交发布准备**

```bash
git add LICENSE README.md docs/superpowers/specs/2026-08-05-first-public-release-design.md docs/superpowers/plans/2026-08-05-first-public-release.md
git commit -m "docs: prepare first public release"
```

- [ ] **Step 4: 创建公开仓库并推送**

Run: `gh repo create alickfine/apple-music-playlist-helper --public --source=. --remote=origin --push`

Expected: 远程创建成功，当前分支设置上游，GitHub 返回公共仓库 URL。

- [ ] **Step 5: 核对远程状态**

Run: `git status -sb && git remote -v && gh repo view alickfine/apple-music-playlist-helper --json url,visibility,defaultBranchRef`

Expected: 工作树干净、`origin` 指向新仓库、可见性为 `PUBLIC`、默认分支指向当前分支。

### Task 3: 提炼并校验 Obsidian 项目档案

**Files:**
- Create: `AlickFine/Codex归档/01-项目/Apple Music 播放列表技能/00-概览.md`
- Modify: `AlickFine/Codex归档/00-本机Codex归档清单.md`

**Interfaces:**
- Consumes: GitHub URL、当前提交、README、测试结果和真实播放列表验收结论。
- Produces: 单一规范项目概览与可检索清单入口。

- [ ] **Step 1: 创建规范项目概览**

使用 `project-overview.md` 模板，写入 `status: completed`、脱敏来源、架构、安全边界、验证证据和 GitHub 入口。

- [ ] **Step 2: 更新归档清单**

在项目表中增加“Apple Music 播放列表技能”一项，并同步清单的 `last_verified`，不改动无关条目。

- [ ] **Step 3: 运行归档校验**

Run:

```bash
python3 /Users/macmini/.agents/skills/obsidian-project-archive/scripts/validate_archive.py \
  "Codex归档/01-项目/Apple Music 播放列表技能/00-概览.md" \
  "Codex归档/00-本机Codex归档清单.md"
```

Expected: 两个文件全部通过 UTF-8、YAML、单一 H1、链接、非空、敏感模式和路径校验。

- [ ] **Step 4: 核对 iCloud 容器状态**

Run: `ls -ldO 'Codex归档/01-项目/Apple Music 播放列表技能' 'Codex归档/00-本机Codex归档清单.md'`

Expected: 文件位于 AlickFine iCloud 容器且本机可读，没有离线占位错误。
