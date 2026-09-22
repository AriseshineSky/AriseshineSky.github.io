---
title: "Pi 高效使用学习规划：官方视角下的进阶路线"
date: 2026-09-22 09:00:00 -0500
categories: [Tools, AI]
tags: [pi, coding-agent, cli, ai-assistant, workflow]
description: >-
  以 pi 官方文档为纲、结合本机实际配置（模型、prompts、agents、skills、extensions）的
  系统性学习规划：先理解官方设计哲学，再按「界面 → 会话 → 项目 → 模型 → 技能 →
  自动化 → 安全」七层递进，附 30 天四周路线与改进建议清单。
---

> 完整分章笔记见仓库 [`pi-notes/`](https://github.com/AriseshineSky/AriseshineSky.github.io/tree/master/pi-notes)，导航页：[Pi 学习笔记](/pi-learning/)。

## 为什么要系统学 pi

我已经能用 pi 完成日常 coding：安装、配 token、对话驱动它改代码。但「能用」和「高效」之间隔着一层**心智模型**——pi 官方在设计上有明确主张：核心保持最小、一切可扩展、不内置一堆功能。不理解这套哲学，就会把 pi 当普通聊天工具用，浪费它最值钱的部分：

- **上下文管理**（会话树、compaction、prompt 缓存）→ 决定长任务质量与成本
- **复用层**（Skills / Prompt Templates）→ 决定你的经验能不能沉淀
- **定制层**（Extensions / Packages / sub-agent）→ 决定 pi 是否贴合你的工作流

本规划按官方文档（README + `docs/`）提炼，结合你本机继承来的配置逐项盘点，给出可执行的 30 天路线。

## 官方希望你如何用 pi

| 原则 | 含义 | 落地 |
|------|------|------|
| 直接对话，别过度指挥 | 模型自带 read/write/edit/bash，自己决定怎么干活 | 描述目标 + 约束，而不是命令序列 |
| 让上下文只装有用信息 | footer 实时显示 token/cost/ctx% | 长任务 `--name` 命名、`/compact` 带指令、独立小问答用 `--no-session` |
| 会话是一棵树 | `/tree` 任意回退分支，历史全保留 | 大胆试、随时分叉，别怕「走错」 |
| 知识渐进披露 | 技能只在匹配时加载完整指令 | description 要写具体（见 06） |
| 工作流由你定义 | 官方只给积木：Skills/Templates/Extensions/Packages | 把重复动作沉淀成技能与模板 |

> 一句话：**pi 不规定你怎么工作，它把「定义工作流的能力」交给你。** 学习 pi 的过程，本质是学会用它的四层积木搭建自己的开发流程。

## 快速上手速查（先抄这三张表）

**10 个最常用命令**

| 输入 | 作用 |
|------|------|
| `@文件名` | 引用项目文件 |
| `!git status` | 执行 shell 并把结果喂给模型 |
| `Ctrl+L` | 切换模型（选择器内 Ctrl+S 存默认） |
| `Shift+Tab` | 循环 thinking 级别（off→max） |
| `Enter` / `Alt+Enter` | 排队「转向」/「后续」消息 |
| `/tree` | 会话树：回退、分叉、打标签 |
| `/compact 说明` | 手动压缩上下文 |
| `/fork` | 从某历史点另起新会话 |
| `/session` | 看 token/成本明细 |
| `pi -p` | 非交互打印模式（脚本友好） |

**写上下文的关键文件**

- `AGENTS.md`（全局 + 项目）→ 项目约定与常用命令，每次启动自动加载（见 04）
- `.pi/settings.json` → 项目级设置覆盖（见 04/05）
- `skills/`、`prompts/`、`extensions/` → 三层复用积木（见 06/07/09）

## 三十天路线（四周）

| 周 | 主题 | 对应章节 | 核心成果 |
|----|------|---------|---------|
| 1 | 界面熟练 + 会话管理 | [02](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/02-interactive.md) [03](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/03-sessions.md) | 快捷键形成肌肉记忆；会用 `/tree` `/compact`；看懂 footer 成本 |
| 2 | 项目化 + 模型策略 | [04](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/04-context-files.md) [05](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/05-models.md) | 每个主力项目有 AGENTS.md；scoped-models 收窄；thinking 升降有意识 |
| 3 | 沉淀复用 | [06](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/06-skills.md) [07](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/07-prompt-templates.md) | 至少 1 个自己的技能、2 个打磨过的模板 |
| 4 | 自动化 + 安全 | [08](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/08-cli.md) [09](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/09-extensions.md) [10](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/10-security.md) | `pi -p` 脚本化；扩展源码审查完；配置 git 化 |

每日节奏建议：早上 `pi -c` 续昨任务 → 午间 `pi -p` 只读审查一段 diff → 晚间 30 分钟读一章 + 完成章末练习。

## 现状盘点（2026-09）

- ✅ 已有：15 个技能（语言框架/代码审查/Google 服务/搜索）、4 个 prompt 模板、4 个 agents、compaction + retry 已启用、catppuccin 主题
- ⚠️ 风险：extensions 为继承配置，**尚未逐一审查**（P0 事项）
- 🎯 最值得先做：全局 AGENTS.md、/scoped-models 收窄、把「发布博客」沉淀成技能

完整盘点与改进建议清单见 [11-audit-roadmap](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/11-audit-roadmap.md)（含四周验收标准与季度评审项）。

## 阅读顺序

1. [01 设计哲学与心智模型](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/01-overview.md) —— 先建心智，再看操作
2. [02 交互界面](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/02-interactive.md)、[03 会话与上下文](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/03-sessions.md)
3. [04 上下文文件](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/04-context-files.md)、[05 模型与成本](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/05-models.md)
4. [06 Skills](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/06-skills.md)、[07 Prompt Templates](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/07-prompt-templates.md)
5. [08 CLI 自动化](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/08-cli.md)、[09 扩展与 sub-agent](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/09-extensions.md)、[10 安全与维护](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/10-security.md)
6. [11 盘点与路线](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/pi-notes/11-audit-roadmap.md)

> 官方文档树在本机：`~/.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/docs/`；反馈/学习社区：官方 Discord、`examples/` 目录、pi 官方博客。