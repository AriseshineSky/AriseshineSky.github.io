# 07 · 速查表

## 选型

| 我想… | 用 |
|-------|----|
| 全站链接更快、少闪白 | Drive |
| 只更新一块 UI | Frame |
| 一次改多处 / 实时推送 | Stream |
| 给 DOM 加行为 | Stimulus |
| App Store 壳 + Web 内容 | Turbo Native |

## Drive 属性

| 属性 | 作用 |
|------|------|
| `data-turbo="false"` | 禁用 Turbo |
| `data-turbo-action` | `advance` / `replace` / `restore` |
| `data-turbo-method` | 非 GET 链接 |
| `data-turbo-confirm` | 确认 |
| `data-turbo-preload` | 预载入缓存 |
| `data-turbo-stream` | GET 也谈 Stream |
| `data-turbo-frame` | 指定 Frame / `_top` |
| `data-turbo-prefetch="false"` | 关预取 |

## Frame 属性

| 属性 | 作用 |
|------|------|
| `id` | 必须；与响应对应 |
| `src` | 懒/急加载 URL |
| `loading` | `lazy` / `eager` |
| `disabled` | 不拦截内部导航 |
| `refresh="morph"` | morph 方式刷新 |
| `target` | 默认导航目标 Frame |

## Stream actions

`append` · `prepend` · `replace` · `update` · `remove` · `before` · `after` · `refresh`  
（`replace`/`update` 可加 `method="morph"`）

## MIME

```text
text/vnd.turbo-stream.html
```

## 事件（高频）

`turbo:before-visit` · `turbo:load` · `turbo:before-fetch-request` · `turbo:submit-end` · `turbo:frame-load` · `turbo:before-stream-render`

## 易错点

1. 用 `DOMContentLoaded` 做每页初始化 → 改用 `turbo:load`
2. Frame 响应缺少同 id → 导航失败/异常
3. Stream 源挂在会被替换的 `<body>` 深处 → 导航后断连；放持久区域
4. 全局监听器重复绑定 → 用 Stimulus 或先 `removeEventListener`
5. 只做 Stream、不做无 JS 降级 → 实时一挂全站不可用

## 官方链接

- https://turbo.hotwired.dev/handbook/introduction
- https://turbo.hotwired.dev/handbook/drive
- https://turbo.hotwired.dev/handbook/frames
- https://turbo.hotwired.dev/handbook/streams
- https://github.com/hotwired/turbo
