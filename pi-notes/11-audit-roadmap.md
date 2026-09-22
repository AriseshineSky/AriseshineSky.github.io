# 11 · 现状盘点 + 30 天学习路线

> 本章是「你的 pi 之旅」的起点索引：先看清手里有什么，再按路线逐项落地。更新日期 2026-09。

## 一、现状盘点

### 配置（`~/.config/pi/agent/`）

| 项 | 当前值 | 评价 |
|----|--------|------|
| theme | catppuccin-mocha（git 包） | 视觉 OK，可留 |
| defaultProvider / Model | qwen-token-plan / deepseek-v4-flash-0731 | 可用；见下改进项 |
| defaultThinkingLevel | medium | 合理 |
| enabledModels | flash / pro / glm-5.2 / grok-4.6 | 建议收窄 scoped-models |
| compaction | enabled, reserve 16384, keep 20000 | 与默认一致，可按模型调优 |
| retry | enabled, 3 次 | 保持 |
| defaultProjectTrust | ask | 安全取向，建议保持 |
| packages | catppuccin、pi-free | 装包前审查（10 章） |
| keybindings | ctrl+y → resume | 可继续加常用绑定 |

### prompts（4 个）与 agents（4 个）与 skills（15 个）

- prompts：`debug` `investigate` `refactor` `review`（review 质量高，其余建议逐个打磨）
- agents：`planner` `reviewer` `scout` `worker`（配合 worker-orchestration 技能）
- skills：语言框架 5 + 代码质量 2 + 工作流 2 + 外部服务 6（详见 06 盘点表）

### extensions（继承自他人，未全部验证）

git/commit/filter-output、subagent/worker/herdr-agent-state、safety、memory/context/impeccable、autoname/usage/fast/ask-question/ui、english-coach/thinking-translation/telegram —— **10 章建议的源码审查与逐个试用是当务之急**。

## 二、改进建议清单（按优先级）

### P0 · 安全与理解（本周内）

1. 逐一审读 `extensions/` 源码，不认识的禁掉（`pi config` 或移出目录）
2. 检查 `trust.json`，清理陌生项目的信任
3. 读 `/skill:memory` 文档，确认 memory 技能用法（此后每轮复杂任务都会用到）

### P1 · 效率基线（第 1 周）

4. 建立全局 `AGENTS.md`（你的通用偏好与禁止事项）
5. 为主要项目写项目 `AGENTS.md`（约定 + 常用命令）
6. `/scoped-models` 收窄 Ctrl+P 循环到 2~3 个模型
7. 配置 shell alias（`p`/`pc`/`prev`/`prevw` 等，见 08）
8. 习惯：大任务 `--name` 命名、`/compact` 带指令、`!command` 喂上下文

### P2 · 复用层（第 2~3 周）

9. 把「发布博客到 GitHub Pages」做成 `site-publish` 技能（06 练习）
10. 打磨 4 个 prompt 模板；新增 `/commit`、`/publish` 模板
11. 为你的高频任务再造 1~2 个专属技能（如 Rails 迁移审查、ES 索引变更复核）
12. 给大窗口模型加 `compaction.modelOverrides`

### P3 · 自动化与编排（第 3~4 周）

13. 用 `pi -p` + `--tools read,grep,find,ls` 做每日 diff 总结/只读审查
14. 用 worker-orchestration 方法论跑通一次「并行拆分 + 验收」的大任务
15. 体验 tmux 多 pi 并行工作流
16. 配置目录纳入 git 管理（排除密钥）

## 三、30 天路线（四周主题）

| 周 | 主题 | 每天 30~60 分钟 |
|----|------|----------------|
| 第 1 周 | 把界面用熟（02/03） | 快捷键、消息队列、`/tree` 分支、`/compact`、成本 footer 读法 |
| 第 2 周 | 项目化与模型策略（04/05） | AGENTS.md、project trust、scoped-models、thinking level 升降 |
| 第 3 周 | 沉淀复用（06/07） | 造 1 个技能、改 2 个模板、description 打磨 |
| 第 4 周 | 自动化与安全（08/09/10） | alias、`pi -p` 脚本、扩展源码审查、tmux、配置 git 化 |

**每日模板**：早上 `pi -c` 续昨天任务 → 午间 `pi -p` 只读审查一段 diff → 晚上 30 分钟学一章 + 完成该章练习。

## 四、验收标准（四周后自检）

- [ ] 能不看笔记说出 10 个以上斜杠命令与 6 个快捷键的用途
- [ ] 大任务会主动命名会话、用 `/tree` 回退分支、`/compact` 带指令
- [ ] 每个主力项目都有 AGENTS.md，且 pi 的行为明显「懂项目」
- [ ] 有 2 个以上自己的技能/模板在真实工作中被自动触发
- [ ] 已审查全部继承扩展，配置目录 git 化
- [ ] 能随口说出当前任务的模型 + thinking 级别 + 大致成本

## 五、持续跟踪

- 每次大版本更新后看 `/changelog`，把新命令/新特性补进对应笔记
- 季度评审：默认模型是否仍最优、技能库是否需要瘦身、（安全方面）重新审视信任列表
- 深入学习材料：官方 `examples/`、官方博客 pi-dev、`docs/extensions.md`（写扩展时）