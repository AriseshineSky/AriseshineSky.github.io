# Pi 高效使用学习笔记

以 [pi 官方文档](https://github.com/earendil-works/pi)（README + `docs/`）为纲，面向「已能完成基本 coding、想系统掌握官方推荐用法」的用户整理的学习路线。配套导读博文与导航页见站点「[Pi 学习笔记](/pi-learning/)」。

## 目录

| 章节 | 主题 | 一句话 |
|------|------|--------|
| [01-overview.md](01-overview.md) | 设计哲学与心智模型 | pi 核心最小、一切可扩展；官方希望你「直接对话 + 按需扩展」 |
| [02-interactive.md](02-interactive.md) | 交互界面 | `@` 引用、`!command`、斜杠命令、快捷键、消息队列 |
| [03-sessions.md](03-sessions.md) | 会话与上下文管理 | 会话是树：`/tree`、`/fork`、compaction、成本监控 |
| [04-context-files.md](04-context-files.md) | 上下文文件与项目配置 | `AGENTS.md`、`.pi/settings.json`、project trust |
| [05-models.md](05-models.md) | 模型与成本策略 | 模型切换、thinking levels、compaction 参数调优 |
| [06-skills.md](06-skills.md) | Skills 技能 | 渐进式披露、现有技能盘点、让 pi 帮你造技能 |
| [07-prompt-templates.md](07-prompt-templates.md) | 提示模板 | `/name` 展开、参数化、现有模板改进 |
| [08-cli.md](08-cli.md) | 非交互模式与自动化 | `pi -p`、管道、`--tools`、shell alias、tmux |
| [09-extensions.md](09-extensions.md) | 扩展与 Sub-agent 工作流 | extensions 盘点、agents + worker-orchestration、packages |
| [10-security.md](10-security.md) | 安全与维护 | project trust、包审查、更新习惯 |
| [11-audit-roadmap.md](11-audit-roadmap.md) | 现状盘点 + 30 天路线 | 配置审计、改进建议清单、四周学习计划 |

## 学习顺序建议

1. **先读 01** 建立心智模型 —— 这决定了后面所有内容怎么用
2. **02 → 03** 是日常效率核心：界面熟练度 + 会话管理，值得反复练
3. **04 → 05** 是「项目级 + 成本级」配置，在你开始把 pi 用于正式项目时最有用
4. **06 → 07** 是复用层：把你的重复操作沉淀成技能和模板（官方最推荐的进阶方向）
5. **08 → 10** 是进阶与维护：自动化、sub-agent 工作流、安全习惯
6. **11** 是评估与路线图：按「改进建议清单」逐项落地

## 配套资源

- 官方文档树：`~/.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/docs/`
- 官方示例：同目录 `examples/`（extensions / sdk）
- 导读博文：[Pi 高效使用学习规划](/posts/pi-learning-guide/)（本系列入口）

## 约定

- 命令、快捷键以 2026-09 的 pi 版本为准；版本更新后以 `pi --help` 与 `/hotkeys` 为准
- 本机配置目录为 `~/.config/pi/agent/`（会话存档在 `~/.config/pi/agent/sessions/`）
- 笔记中的「练习」均为可独立完成的小任务，完成即意味着该知识点已上手