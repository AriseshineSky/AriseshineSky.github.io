---
icon: fas fa-terminal
order: 3
---

# Pi 学习笔记

以 [pi 官方文档](https://github.com/earendil-works/pi)（README + `docs/` + `examples/`）为纲，结合本机实际配置整理的 pi 高效使用学习路线。目标：从「能完成基本 coding」进阶到「按官方推荐的方式高效使用」，并把自己的工作流沉淀为技能与模板。

## 导读

- [Pi 高效使用学习规划](/posts/pi-learning-guide/) — 设计哲学、速查表、四周路线与现状盘点

## 分章笔记（仓库内）

源文件在站点仓库 [`pi-notes/`](https://github.com/AriseshineSky/AriseshineSky.github.io/tree/master/pi-notes)：

1. [设计哲学与心智模型](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/01-overview.md)
2. [交互界面](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/02-interactive.md)
3. [会话与上下文管理](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/03-sessions.md)
4. [上下文文件与项目配置](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/04-context-files.md)
5. [模型与成本策略](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/05-models.md)
6. [Skills 技能](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/06-skills.md)
7. [Prompt Templates 模板](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/07-prompt-templates.md)
8. [非交互模式与自动化](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/08-cli.md)
9. [扩展与 Sub-agent 工作流](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/09-extensions.md)
10. [安全与维护](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/10-security.md)
11. [现状盘点与 30 天路线](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/11-audit-roadmap.md)

## 推荐阅读顺序

1. 先读导读博文建立心智模型
2. 01（哲学）→ 02（界面）→ 03（会话）—— 日常效率核心
3. 04（AGENTS.md）→ 05（模型策略）—— 项目级落地
4. 06（技能）→ 07（模板）—— 沉淀复用
5. 08（CLI）→ 09（扩展）→ 10（安全）—— 进阶与维护
6. 用 11（盘点路线）做季度评审

## 本机相关资源

- 官方文档树：`~/.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/docs/`
- 官方示例：同目录 `examples/`（extensions / sdk）
- 配置目录：`~/.config/pi/agent/`（settings / prompts / agents / skills / extensions / sessions）