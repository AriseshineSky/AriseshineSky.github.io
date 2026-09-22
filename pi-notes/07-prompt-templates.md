# 07 · Prompt Templates 提示模板

## 是什么

Markdown 片段，`/模板名` 展开为 prompt。适合**你有固定提问套路**的场景——比技能更轻（纯文本、无脚本），适合 prompt 层复用。

- 目录：`~/.config/pi/agent/prompts/`（全局）、`.pi/prompts/`（项目）、包内 `prompts/`
- 文件名即命令名：`review.md` → `/review`
- frontmatter `description`：显示在自动补全里，建议写清楚用途
- frontmatter `argument-hint`：显示参数提示，如 `argument-hint: "<PR-URL>"`

## 参数

| 写法 | 含义 |
|------|------|
| `$1` `$2` | 位置参数 |
| `$@` / `$ARGUMENTS` | 全部参数连接 |
| `${1:-default}` | 有参用参，无参用默认 |
| `${@:-default}` | 同上，针对全部参数 |
| `${@:N}` / `${@:N:L}` | 从第 N 个起 / 取 L 个 |

```markdown
---
description: Review PRs from URLs with structured issue and code analysis
argument-hint: "<PR-URL>"
---
分析这个 PR：$1
- 列出 bug 与安全风险
- 指出测试缺口
- 给出修改建议（按文件组织）
```

`/review https://github.com/xxx/pull/1` 即展开。

## 现有模板盘点（4 个，全局 prompts/）

| 模板 | 用途 | 观察 |
|------|------|------|
| `review.md` | 审查未提交/staged 的 git 改动（正误/安全/性能/可维护，分级报告） | 质量高，可直接用 |
| `debug.md` | 调试排查 | 建议打开看一眼措辞是否具体 |
| `investigate.md` | 代码/问题调查 | 同上 |
| `refactor.md` | 重构 | 建议补上「保持行为不变 + 测试先行」等约束 |

> 注意：user 级模板 + 项目级模板并存时都可用；如果团队项目想共享，放进包的 `prompts/` 或项目 `.pi/prompts/`。

## 改进建议

1. **review.md 参数化**：加 `argument-hint: "[diff范围]"`，正文用 `${1:-git diff --cached}` 让范围可选
2. **新建「提交」模板**：`/commit`（`!git diff --stat` 喂入 → 生成符合项目规范的 message，见 02 练习）
3. **新建「发布」模板**：把 GitHub Pages 发布步骤做成 `/publish`（与 06 的 skill 结合：模板定 prompt、skill 定执行流程）
4. 模板要与你的 AGENTS.md 约定一致（如 Rails 项目要求 RSpec），避免两处打架

## 本节练习

- [ ] 打开全部 4 个现有模板，判断哪些该参数化、哪些描述含糊
- [ ] 写一个 `/commit` 模板并实际用于一次提交
- [ ] 在某个项目 `.pi/prompts/` 里放一个团队共享模板，并让同事试用（体验项目级作用域）