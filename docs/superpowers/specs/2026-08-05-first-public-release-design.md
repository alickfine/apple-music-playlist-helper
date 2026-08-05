# Apple Music 播放列表助手首次公开发布设计

## 目标

把已完成并经真实 Apple Music 中国区验收的本机播放列表助手发布为可公开分享的 GitHub 第一版，同时把可复用知识提炼进 AlickFine Obsidian。

## 发布范围

- 创建公开仓库 `alickfine/apple-music-playlist-helper`。
- 保留当前 `codex/apple-music-helper` 分支与既有提交历史。
- 增加 MIT 许可证文件，版权标识使用 `AlickFine`。
- 在 README 增加从 GitHub 克隆、安装 Skill 和自然语言调用的最短路径。
- 不改动 Swift 源码、Skill 行为、Apple Music 播放列表或本机权限。

## 验证门

- `swift test` 全部通过。
- `swift build -c release` 成功。
- 五个 `Tests/SkillPackageTests/*.sh` 均通过。
- 分发目录不存在开发者绝对路径、凭据、预编译二进制或 `.build`。
- Git 工作树的发布变更仅包括许可证、README、发布设计和实施计划。

## GitHub 交付

- 首次创建公开仓库，不覆盖任何既有远程仓库。
- 添加 `origin` 后推送当前分支并建立跟踪关系。
- 新仓库以当前首次推送分支作为默认分支；因不存在独立基线分支，不额外创建空白 PR。
- 不创建 Release、Tag、GitHub Actions、Issue 或其他未授权对象。

## Obsidian 归档

- 首次创建 `Codex归档/01-项目/Apple Music 播放列表技能/00-概览.md`。
- 记录目标、架构、安全边界、自然语言用法、验证证据、GitHub 入口与已知限制。
- 更新 `Codex归档/00-本机Codex归档清单.md`，不改变无关条目和统计口径。
- 不保存账号信息、播放列表明细、目录查询日志、删除收据或任何凭据。

## 完成标准

- GitHub 公共 URL 可访问，远程分支与本地提交一致。
- Obsidian 概览与清单通过归档校验脚本，并处于 iCloud 专用容器中。
- 最终报告提交哈希、分支、远程 URL、验证结果、归档路径和待确认项。
