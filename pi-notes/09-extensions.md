# 09 · 扩展与 Sub-agent 工作流

## Extensions 是什么

TypeScript 模块，通过钩子扩展 pi：注册自定义工具、命令、快捷键、处理事件（`tool_call`、`turn_end`、`agent_before_settle` 等）、画自定义 UI。

```typescript
export default function (pi: ExtensionAPI) {
  pi.registerTool({ name: "deploy", ... });
  pi.registerCommand("stats", { ... });
  pi.on("tool_call", async (event, ctx) => { ... });
}
```

放 `~/.config/pi/agent/extensions/`（全局）或 `.pi/extensions/`（项目，需信任）。**官方对扩展的定位**：上面 01 章列的那些「不内置」功能（sub-agents、权限流、plan mode、MCP……）就是官方期待你用扩展/包补上的。

## 本机扩展盘点（extensions/ 目录）

| 类别 | 目录/文件 | 推测用途 |
|------|----------|---------|
| Git 工作流 | `git.ts`、`commit`、`filter-output` | git 工具、自动 commit、输出过滤 |
| 委托/子代理 | `subagent`、`worker`、`herdr-agent-state.ts` | 子代理与 worker 编排、agent 状态 |
| 安全 | `safety.ts` | 路径/命令保护 |
| 记忆与上下文 | `memory`、`context`、`impeccable` | indexed memory、上下文管理 |
| 会话体验 | `autoname`、`usage`、`fast`、`ask-question`、`ui` | 自动命名、用量统计、快速模式、提问 UI |
| 附属能力 | `english-coach`、`thinking-translation`、`telegram` | 英语陪练、思考翻译、Telegram 接入 |

> 这些是**继承来的配置**。学 pi 的过程也是「审计配置」的过程：逐个用 `/reload` 后实际触发一次，判断对自己有没有用（见 11 的清理清单）。不要因为「别人有我就该有」——哲学是工作流由你定义。

## Agents + Worker Orchestration：你的 sub-agent 方案

官方不内置 sub-agents，但你的配置里已有一套：

- `agents/` 目录：`planner`（出实现计划，只读）、`reviewer`、`scout`、`worker` —— 带角色与工具约束的提示词
- `worker-orchestration` 技能：指导如何把大任务拆分、路由（Fast/Normal/Deep/Max）、并行、审阅、验收
- 配套扩展：`subagent`、`worker`

**学习路径**：先用 `/skill:worker-orchestration` 读一遍它的方法论 → 在小任务上试用 `worker`（或 subagent 工具）拆分 → 再决定要不要深入定制。

## Pi Packages：共享与批量安装

```bash
pi install npm:@foo/pi-tools          # npm
pi install git:github.com/user/repo   # git
pi install -l ...                     # 项目本地
pi list                               # 列出已装
pi update --all                       # 更新 pi + 全部包
pi update --models                    # 刷新模型目录
pi config                             # 启用/禁用包内资源（扩展/技能/模板/主题）
```

你当前已装：`git:catppuccin`（主题）、`npm:pi-free`（免费模型相关）。**注意安装前审查源码**（见 10）。

## 何时需要自己写扩展

| 场景 | 建议 |
|------|------|
| 想复用工作流 | 先考虑 Skills（06）——多数情况够用 |
| 想固定提问套路 | Prompt Templates（07） |
| 想让 pi 行为变化（新工具/命令/事件） | Extensions |
| 想分享给别人 | 打成 Package |

官方示例在 `examples/extensions/`（custom-compaction、agent orchestration 等），SDK/RPC 玩法见 `docs/sdk.md`、`docs/rpc.md`（把 pi 嵌进你自己的应用）。

## 本节练习

- [ ] `pi list` 查看已装包；`pi config` 看每个包启用了什么
- [ ] 逐个触发你关心的扩展（用 `/hotkeys` 与 startup header 找名字），判断留/删
- [ ] 读一遍 `examples/extensions/` 里 custom-compaction 或 git-checkpoint 示例，理解扩展骨架
- [ ] 用 worker-orchestration 技能里的方法，把一个明显可并行的大任务拆给 worker，做一次完整验收