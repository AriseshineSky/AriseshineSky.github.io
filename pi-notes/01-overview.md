# 01 · 设计哲学与心智模型

## pi 是什么

> A minimal terminal coding harness.

pi 是一个「最小」的终端编码智能体：核心只做一件事——把 LLM 和你的文件系统/终端安全地连接起来，其余全部通过扩展获得。

启动后默认给模型四个工具：`read`、`write`、`edit`、`bash`（另有 `grep`、`find`、`ls`）。**官方推荐的使用方式就是：直接对话，让模型自己决定何时用哪个工具。** 你不需要像传统 prompt 工程那样一步步指挥它。

## 官方设计原则（Philosophy）

这是整个学习路线的「纲」。pi 明确**不内置**以下功能，并给出官方认可的替代方案：

| 其他工具内置的功能 | pi 的态度 | 官方的替代方案 |
|------------------|----------|---------------|
| MCP | 不内置 | 写 CLI 工具 + Skills；或写扩展加 MCP 支持 |
| Sub-agents | 不内置 | 用 tmux 跑多个 pi；用扩展实现；装现成包 |
| 权限弹窗 | 不内置 | 放容器里跑；用扩展实现符合自己环境的确认流 |
| Plan mode | 不内置 | 把计划写进文件（模型擅长写作计划） |
| To-dos | 不内置 | 用 `TODO.md` 文件（官方认为内置 to-do 会混淆模型） |
| 后台 bash | 不内置 | 用 tmux（完全可观测、可直接交互） |

**推论（对你很重要）：** 你继承的配置里已经有 `subagent`、`worker`、`safety`、`commit`、`git.ts` 等扩展——这些正是社区/他人按上述哲学「用扩展补齐」的产物。理解了这个哲学，你就能判断一个「别人身上的配置项」该不该留。

## 扩展的四个层次

| 层次 | 是什么 | 什么时候用 | 成本 |
|------|--------|-----------|------|
| Prompt Templates | 可复用的 prompt 片段（`/name` 展开） | 有固定提问套路时 | 最低：纯文本 |
| Skills | 按需加载的能力包（SKILL.md + 脚本） | 有可复用的工作流时 | 低：markdown + 可选脚本 |
| Extensions | TypeScript 钩子：工具/命令/事件/UI | 需要改变 pi 行为本身时 | 中：要写 TS |
| Packages | 把上面三者打包分发（npm/git） | 想共享或批量安装 | 低 |

> 官方原文："Pi is aggressively extensible so it doesn't have to dictate your workflow." —— pi 激进地可扩展，正因如此它不必规定你的工作流。**你的工作流由你定义，pi 提供积木。**

## 三个关键心智模型

### 1. 上下文是稀缺资源

模型有上下文窗口上限。pi 的 footer 会实时显示 token 用量（`↑` 输入、`↓` 输出、`R` 缓存读、`W` 缓存写、`CH` 缓存命中率）、cost 与 context 使用率。所有效率技巧最终都围绕一件事：**让上下文里装的都是有用信息**。

- 长历史会自动 compaction（见 03）
- 判断「何时开新会话」也是一种上下文管理

### 2. 会话是一棵树

每个会话是 JSONL 文件里的树。你可以从任意历史节点继续并生出新分支，所有历史都保留（见 03 的 `/tree`）。**pi 鼓励你大胆尝试分支，而不是小心翼翼地维护单一线性对话。**

### 3. 知识是渐进披露的

Skills 的**完整指令默认不在上下文中**，只有 name + description 常驻。模型只有在任务匹配描述时才加载完整 SKILL.md。这保证了上下文干净、技能可以很多。（见 06）

## 官方文档地图

| 你要找什么 | 读哪里 |
|-----------|--------|
| 一天内必须会的用法 | `README.md`（Quick Start → Interactive Mode → Sessions） |
| 全部斜杠命令/快捷键 | `docs/usage.md`、`docs/keybindings.md` |
| 会话/压缩细节 | `docs/sessions.md`、`docs/compaction.md` |
| 设置项全表 | `docs/settings.md` |
| 技能怎么写 | `docs/skills.md` |
| 模板怎么写 | `docs/prompt-templates.md` |
| 扩展怎么写 | `docs/extensions.md` + `examples/extensions/` |
| 模型/provider 配置 | `docs/models.md`、`docs/providers.md`、`docs/custom-provider.md` |
| CLI 全参 | README 的 CLI Reference + `pi --help` |
| 版本变化 | `/changelog`、`pi update --self` |

> 设计层面的完整论述见官方博客：《pi coding agent》(mariozechner.at)。

## 本节练习

- [ ] 用 `/hotkeys` 扫一遍快捷键，把陌生的抄到 02 笔记里
- [ ] 打开 pi，看 startup header 列出了哪些 skills / prompts / extensions —— 对照 06/07/09 的盘点
- [ ] 观察一次大任务：注意 footer 的 `R`/`W` 缓存字段何时变化（这关系到成本）