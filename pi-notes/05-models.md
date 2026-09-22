# 05 · 模型与成本策略

## Provider 与模型切换

- `/model`（或 `Ctrl+L`）打开选择器，`Ctrl+S` 保存为启动默认
- `Ctrl+P` / `Shift+Ctrl+P` 在 `/scoped-models` 配置的集合内前后循环
- 命令行：`pi --model qwen-token-plan/deepseek-v4-pro-0813`、`pi --model sonnet:high`（带思考级别）

你当前配置（settings.json）：
- defaultProvider `qwen-token-plan`、defaultModel `deepseek-v4-flash-0731`、thinking `medium`
- enabledModels：`deepseek-v4-flash-0731`、`deepseek-v4-pro-0813`、`glm-5.2`、`xai/grok-4.6`

**建议**：用 `/scoped-models` 把 `Ctrl+P` 循环限制在 2~3 个你真正切换的模型上（比如 fast 平替 + pro 重活），避免误切到不熟的模型白花钱。

## Thinking levels（思考级别）

`Shift+Tab` 循环：`off / minimal / low / medium / high / xhigh / max`。级别越高，模型先「想」得越久，质量与成本同步上升。

| 任务类型 | 推荐级别 |
|---------|---------|
| 简单问答、格式化、翻译 | `off` ~ `low` |
| 日常编码（改 bug、写测试、重构小范围） | `medium`（你的默认，合理） |
| 架构设计、跨文件大重构、疑难排查 | `high` ~ `xhigh` |
| 极难问题 | `max`（按需，成本高） |

> 优化点：**默认 medium 没问题，但「每次任务手动切级别」本身就是你的成本杠杆**。简单任务降级、复杂任务升级，比换模型更省。

## Compaction 按模型调优

不同模型上下文窗口不同。可以按模型覆盖压缩预算：

```json
{
  "compaction": {
    "reserveTokens": 16384,
    "keepRecentTokens": 20000,
    "modelOverrides": {
      "qwen-token-plan/deepseek-v4-pro-0813": {
        "reserveTokens": 40000,
        "keepRecentTokens": 60000
      }
    }
  }
}
```

大窗口模型（如 pro）可以给更高预算，减少频繁压缩带来的信息损失；小模型保持默认。

## 成本监控习惯

- Footer 常驻显示 cost / token / 缓存
- `/session` 看会话累计
- 缓存策略：**同一会话少换模型、少重复读同一大文件**，prompt 缓存命中率（`CH`）更高、便宜很多

## 本节练习

- [ ] 用 `/scoped-models` 把循环集合设为 2~3 个模型
- [ ] 同一任务分别用 `low` 和 `high` 跑一遍，对比质量与 footer 的 cost
- [ ] 给大窗口模型加一条 `compaction.modelOverrides`，跑长会话验证压缩触发点变化
- [ ] 把「默认模型是否合适」列入 11 章的季度评审项（模型更新很快，别设了就不动）