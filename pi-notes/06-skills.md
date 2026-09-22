# 06 · Skills 技能

## 原理：渐进式披露（progressive disclosure）

- 启动时 pi 扫描技能目录，把每个技能的 `name + description` 放进系统提示
- **完整 SKILL.md 默认不在上下文里**：只有任务匹配 description 时，模型才用 `read` 加载全文
- 所以：**description 写得好不好，直接决定技能会不会被自动想起**
- 强制加载：`/skill:name`；带参：`/skill:name 参数`（参数会以 `User: <args>` 追加到技能内容后）

```
my-skill/
├── SKILL.md          # frontmatter(name/description 必填) + 操作步骤
├── scripts/          # 辅助脚本（可选）
├── references/       # 按需加载的详细文档（可选）
└── assets/           # 模板等资源（可选）
```

**frontmatter 要点**：`name`（小写字母数字连字符）、`description`（具体！写「何时用、做什么」，不写「帮助处理 PDF」这种废话）、`license`/`allowed-tools` 可选。

## 技能目录（本机实际位置）

- 全局：`~/.config/pi/agent/skills/`（还有 `~/.agents/skills/`）
- 项目（信任后）：`.pi/skills/`、`.agents/skills/`（cwd 向上到 git 根）
- 包：`pi.skills` / `skills/` 目录
- 设置：`settings.json` 的 `skills` 数组可引用外部目录（如 `~/.claude/skills`，**可直接复用 Claude Code 的技能**）

## 现有技能盘点（15 个）

| 技能 | 来自 | 用途 | 触发 |
|------|------|------|------|
| python | 本地 | Python 脚本/爬虫/celery 约定 | 自动/`/skill:python` |
| rails | 本地 | Rails 开发约定与坑 | 自动/`/skill:rails` |
| docker | 本地 | 容器与 compose 运维 | 自动/`/skill:docker` |
| postgres | 本地 | psql、迁移、索引、dump | 自动/`/skill:postgres` |
| elasticsearch | 本地 | ES 查询、mapping、reindex | 自动/`/skill:elasticsearch` |
| code-review | 本地 | 结构化代码审查（正误/安全/性能/可维护） | 自动/`/skill:code-review` |
| neovim | 本地 | 终端里用 nvim 看 diff | 自动/`/skill:neovim` |
| memory | 本地 | 搜索/读取/沉淀 indexed memory | 自动（复杂任务时） |
| worker-orchestration | 本地 | Worker 委派、并行拆分、验收 | 自动（大任务） |
| brave-search | pi-skills | 网页搜索与内容提取 | 自动/`/skill:brave-search` |
| browser-tools | pi-skills | CDP 浏览器自动化、前端测试 | 自动/`/skill:browser-tools` |
| gccli / gdcli / gmcli | pi-skills | Google 日历 / 云盘 / Gmail CLI | 自动/`/skill:gccli` 等 |
| youtube-transcript | pi-skills | 取 YouTube 字幕做总结 | 自动/`/skill:youtube-transcript` |

> 结论：你的技能库已经很完整：语言框架 5 个、代码质量 2 个、效率工作流 2 个、外部服务 6 个。**下一步不是「收集更多」，而是「让已有的被可靠触发 + 补齐自己项目的专属工作流」。**

## 让 pi 帮你造技能（官方推荐姿势）

> 官方文档第一行就写：*"pi can create skills. Ask it to build one for your use case."*

典型流程：在对话里描述你反复做的事 → 让 pi 写好 SKILL.md 和脚本 → 放到 `~/.config/pi/agent/skills/` → `/reload` 或重启 → 之后自动触发。

## 本节练习

- [ ] 把你刚做的「发布笔记到 GitHub Pages」流程交给 pi，做成一个 `site-publish` 技能
- [ ] 挑一个你的高频重复任务（如「Rails 迁移审查」），让 pi 写技能并试用
- [ ] 检查 2~3 个现有技能的 description 是否具体；含糊的让 pi 重写
- [ ] 用 `/skill:memory` 了解 memory 技能怎么沉淀长期记忆（对你持续学习 pi 有用）