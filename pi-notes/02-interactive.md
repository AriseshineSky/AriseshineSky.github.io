# 02 · 交互界面

## 界面四区

| 区域 | 内容 |
|------|------|
| Startup header | 快捷键提示、已加载的 AGENTS.md / skills / prompts / extensions |
| Messages | 消息、tool 调用与结果、通知、扩展 UI |
| Editor | 输入区；边框颜色 = 当前 thinking 级别；边框上有流式工作指示 |
| Footer | 工作目录、会话名、token/缓存/成本、context 使用率、当前模型 |

**Footer 速读**：`↑ in / ↓ out / R cache-read / W cache-write / CH hit-rate / cost / ctx%`。养成每次看一眼的习惯，比月末看账单有用。

## 编辑器特性（日常高频）

| 操作 | 怎么用 | 场景 |
|------|--------|------|
| 引用项目文件 | 输入 `@` 模糊搜索 | 讨论具体文件，无需先贴代码 |
| 路径补全 | `Tab` | 输入命令/参数时 |
| 多行输入 | `Shift+Enter` | 写长 prompt |
| 外部编辑器 | `Ctrl+G` | 打开 `$EDITOR` 写长消息 |
| 粘贴图片 | `Ctrl+V` / 拖入终端 | 截图报 bug、贴 UI 设计图 |
| 执行 shell 并给模型看 | `!command` | `!git status`、`!rails routes`——结果直接进上下文 |
| 执行 shell 不给模型看 | `!!command` | 想自己确认某事，不想污染上下文 |

## 斜杠命令（按用途分组）

**模型与会话**
- `/model` 切模型（选择器内 `Ctrl+S` 保存为默认）；`Ctrl+L` 快捷打开
- `/thinking` 切思考级别（`Ctrl+S` 保存默认）；`Shift+Tab` 快捷切换
- `/scoped-models` 配置 `Ctrl+P` 循环的模型集合
- `/resume` 浏览历史会话；`/new` 新会话；`/name <name>` 命名

**会话内部**
- `/session` 看会话文件/ID/消息数/token/成本
- `/tree` 跳到任意历史节点继续，或创建分支（`Escape` 两次也打开）
- `/fork` 从某条历史消息另起一个新会话文件
- `/clone` 把当前分支复制为新会话
- `/compact [说明]` 手动压缩上下文（自动压缩见 03）

**工具与系统**
- `/settings` 主题、消息投递、transport 等偏好
- `/trust` 保存项目信任决定（需重启生效）
- `/export [file]` 导出会话 HTML/JSONL；`/import <file>` 导入
- `/share` 上传为私有 GitHub gist（分享用）
- `/reload` 重载 keybindings/extensions/skills/prompts/themes/context files
- `/hotkeys` 全部快捷键；`/changelog` 版本历史
- `/bug [描述]` 给开发者报 bug

## 常用快捷键

| 键 | 动作 |
|----|------|
| `Ctrl+C` | 清空编辑区（连按两次退出） |
| `Escape` | 取消/中止（连按两次开 `/tree`） |
| `Ctrl+L` | 打开模型选择器 |
| `Ctrl+P` / `Shift+Ctrl+P` | 在 scoped models 间前/后循环 |
| `Shift+Tab` | 循环 thinking 级别 |
| `Ctrl+O` | 折叠/展开 tool 输出 |
| `Ctrl+T` | 折叠/展开 thinking 块 |
| `Ctrl+X` | 复制最后一条 assistant 消息（`/tree` 中复制选中消息） |

自定义：`~/.config/pi/agent/keybindings.json`（你已有一个 `ctrl+y → 恢复会话` 的绑定，可继续加）。

## 消息队列（多任务流水线的关键）

模型工作时你可以继续输入，按键决定送达时机：

| 键 | 送达时机 | 典型用法 |
|----|---------|---------|
| `Enter` | 当前 tool 批次结束后（steering） | 中途纠正方向：「那个文件别改了」「先看测试」 |
| `Alt+Enter` | 整轮工作全部结束后（follow-up） | 排队下一个任务 |
| `Escape` | 中止并把排队消息退回编辑器 | 反悔 |
| `Alt+Up` | 把排队消息取回编辑器 | 修改后再发 |

> 这是 pi 相对很多工具的高效点：**不用等模型说完才能说话**。长任务中把「先做 X 再做 Y」排成队，一轮跑完。

投递策略可在 `/settings` 调 `steeringMode` / `followUpMode`（`one-at-a-time` 或 `all`）。

## 本节练习

- [ ] 在一个真实项目里用 `@` 引用 3 个文件让模型对比
- [ ] 用 `!git diff --stat` 把变更摘要喂给模型，写 commit message
- [ ] 长任务中尝试 `Enter` 排队一个转向指令，体会 steering 时机
- [ ] 把 `Ctrl+O`、`Ctrl+T` 用熟：折叠工具输出是保持思路连贯的利器