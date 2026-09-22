# 04 · 上下文文件与项目配置

上下文文件是让 pi「懂你的项目」最便宜的方式 —— 纯文本、无成本、每次启动自动加载。

## AGENTS.md / CLAUDE.md

启动时 pi 从以下位置逐层加载并**拼接**：

1. `~/.pi/agent/AGENTS.md`（全局；本机对应 `~/.config/pi/agent/AGENTS.md`）
2. 从当前目录向上逐级父目录
3. 当前目录

若某目录存在 `AGENTS.override.md`，则用它**替换**该层的 AGENTS.md/CLAUDE.md（其他层照常叠加）。

**放什么**：项目约定、常用命令、安全规则、偏好。示例：

```markdown
# Rails 项目约定
- 数据库迁移必须配套 down 方法；涉及 ES 索引时同步更新 mappings（见 docs/es.md）
- 测试：新增逻辑必须带 RSpec，命令行 `bin/rspec spec/models`
- 禁止把密钥写进代码；统一用 Rails credentials
- 不确定架构归属时先问，不要臆断
```

**收益**：模型每次都能看到这些规则，等于把「团队 onboarding」写进每次对话。官方明确推荐：项目指令、约定、常用命令放这里。

## SYSTEM.md / APPEND_SYSTEM.md

- `.pi/SYSTEM.md`（项目）或 `~/.pi/agent/SYSTEM.md`（全局）：**替换**默认系统提示
- `APPEND_SYSTEM.md`（两处皆可）：**追加**到默认提示后（更安全，推荐先从这里开始）

## .pi/settings.json（项目设置）

| 位置 | 作用域 |
|------|--------|
| `~/.pi/agent/settings.json`（本机 `~/.config/pi/agent/settings.json`） | 全局 |
| `<project>/.pi/settings.json` | 项目级覆盖 |

项目级可放：`skills` 数组（引用项目技能目录）、`compaction` 覆盖、模型偏好等。项目配置需要**项目被信任**才会加载。

## Project Trust（项目信任）

pi 在启动时发现项目含本地设置/资源/`agents/skills` 且无已存决定时，会询问是否信任。信任后才会加载该项目 `.pi/settings.json`、执行项目扩展。

| 手段 | 说明 |
|------|------|
| `/trust` | 交互式保存信任决定（写入 `~/.pi/agent/trust.json`，重启生效；也可信任父目录） |
| settings `defaultProjectTrust` | `ask`（默认）/ `always` / `never` |
| `pi -a` / `-na` | 单次运行覆盖（非交互模式用） |

> 非交互模式（`-p`、json/rpc）不弹窗：按 `defaultProjectTrust` 行为处理，可用 `-a`/`-na` 覆盖。这是自动化脚本里的关键点。

## 本节练习

- [ ] 你的某个正式项目里建一个 `AGENTS.md`：写 3~5 条「模型必须遵守」的约定 + 常用命令
- [ ] 全局建 `~/.config/pi/agent/AGENTS.md`：写你的通用偏好（语言、验证习惯、禁止事项）
- [ ] 用 `pi --no-context-files`（`-nc`）启动一次，感受有/无上下文文件的差别
- [ ] 在 `/trust` 里看一眼已信任的项目列表，思考哪些项目其实不该信任