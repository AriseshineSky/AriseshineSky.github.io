# 08 · 非交互模式与自动化

## 打印模式 `-p`

```bash
pi -p "总结这个仓库"                    # 一句话出结果
cat README.md | pi -p "总结这段文本"    # 管道输入并入 prompt
pi -p @screenshot.png "图里是什么"      # 文件/图片参数
pi --name "release audit" -p "审计本次发布"  # 命名一次性会话
```

适合：脚本、CI、快速问答、不想进交互界面的场景。

## 多文件输入

```bash
pi @prompt.md "回答我"
pi @code.ts @test.ts "审查这些文件"
```

`@` 前缀文件会被并入消息。与 `-p` 组合 = 无头代码审查。

## 工具白名单/黑名单（安全与专注）

```bash
# 只读审查：模型只能看，不能改
pi --tools read,grep,find,ls -p "审查代码"

# 禁用某个内置工具而保留其余
pi --exclude-tools ask_question

# 禁用全部内置工具（只用扩展工具）
pi --no-builtin-tools

# 裸跑：完全不用任何工具，只看对话
pi --no-tools "解释这个概念"
```

内置工具：`read` `bash` `powershell(Win)` `edit` `write` `grep` `find` `ls`。

> 你的扩展还注册了额外工具（memory、ask_question、subagent、worker 等），同样可以用 `--tools`/`--exclude-tools` 精确控制——例如 CI 里跑审查时把 `ask_question` 排除，避免挂起等输入。

## 会话控制

```bash
pi --no-session -p "一次性问题"   # 不落盘
pi -c "继续上次，把 X 做完"        # 续接最新会话并下达指令
pi -r                             # 交互选择历史会话
```

## 模型/思考级别快捷

```bash
pi --model qwen-token-plan/deepseek-v4-pro-0813 "重活"
pi --model "glm-5.2:high" "复杂推理"        # 带思考级别
pi --thinking off -p "格式化这段代码"
```

## 单次信任覆盖

```bash
pi -a   # 单次信任项目本地配置（非交互模式无弹窗时用）
pi -na  # 单次忽略
```

## Shell alias（推荐）

官方专门有一份 [docs/shell-aliases.md](docs/shell-aliases.md)。常用示例（bash/zsh）：

```bash
alias p='pi'                       # 短命令
alias pc='pi -c'                   # 继续最近会话
alias pr='pi -r'                   # 浏览会话
alias preg='pi --no-session'       # 临时问答
alias prev='pi -p'                 # 打印模式
alias pno='pi --no-tools -p'       # 纯问答
alias prevw='pi --tools read,grep,find,ls -p'  # 只读审查
```

## tmux：后台长任务与多实例

官方不内置后台 bash / sub-agents，推荐 tmux：

```bash
tmux new -s sess1                    # 起一个 pi 会话做重活
tmux new -s sess2                    # 同时开另一个 pi 做别的事
tmux attach -t sess1                 # 随时回来交互
```

多个 pi 实例并行 = 官方认可的「sub-agent 替代方案」之一（另一种见 09 的扩展方案）。

## 本节练习

- [ ] 给 shell 配置 3~5 个别名并实际使用一周
- [ ] 写一个每天运行的 cron/脚本：`git diff $(date -d yesterday) | pi --tools read -p "总结昨日变更"`（先确认 git 命令语法）
- [ ] 在 CI 或本地脚本里跑一次只读代码审查：`pi --tools read,grep,find,ls -a -p @src/ "按 code-review 技能审查"`