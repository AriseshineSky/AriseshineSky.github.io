---
title: "Hotwired Turbo 学习总结：Drive / Frames / Streams"
date: 2026-07-28 09:40:00 -0500
categories: [JavaScript, Rails]
tags: [turbo, hotwire, stimulus, html-over-the-wire, spa]
description: >-
  基于 hotwired/turbo 8.x 源码与官方 Handbook 的中文学习总结：HTML over the Wire 理念，
  Turbo Drive / Frames / Streams / Native 选型，以及对照源码的阅读路径。
---

> 笔记对照 [hotwired/turbo](https://github.com/hotwired/turbo)（约 **8.0.23**）与 [Turbo Handbook](https://turbo.hotwired.dev/handbook/introduction)。完整分章与速查表见仓库 [`turbo-notes/`](https://github.com/AriseshineSky/AriseshineSky.github.io/tree/master/turbo-notes)，导航页：[Turbo 学习笔记](/turbo-learning/)。

## 1. Turbo 是什么

Turbo 用一套互补技术，让 Web 应用**少写自定义 JS**，同时获得接近 SPA 的速度：

| 模块 | 一句话 | 典型场景 |
|------|--------|----------|
| **Drive** | 拦截同域链接与表单，`fetch` 后替换 `<body>`、合并 `<head>` | 整站加速，替代整页刷新 |
| **Frames** | `<turbo-frame>` 把页面切成独立导航上下文 | 侧边栏、内联编辑、Tab、懒加载 |
| **Streams** | `<turbo-stream action="…">` 声明式改 DOM | 表单后多处更新、WebSocket 实时列表 |
| **Native** | Web 内容嵌在原生壳里 | Basecamp / HEY 式混合 App |

核心理念是 **HTML over the Wire**：业务逻辑留在服务端，浏览器只处理最终 HTML。需要细粒度行为时，再配 [Stimulus](https://stimulus.hotwired.dev)。

```text
用户点击 / 提交
    ├─ 在 Frame 内？ → 只换同 id 的 <turbo-frame>
    ├─ 响应是 Stream？ → 按 action 改多处 DOM
    └─ 否则 Drive → 换 body，保留 window / document
```

## 2. 为什么选这条路

| 对比 | SPA | Turbo |
|------|-----|-------|
| 页面数据 | JSON | HTML |
| 导航 | 客户端 Router | Drive |
| 局部更新 | 组件 re-render | Frames / Streams |
| 业务逻辑 | 前后端各一份 | 主要在服务端 |

适合服务端渲染应用（Rails、Laravel、Django…），以及希望先做出「够快」的体验、再按需加 JS 的团队。

## 3. Turbo Drive

同域 `<a>` 与表单提交变成后台请求：History API 改 URL → `fetch` → 渲染。跨页时 **`window` / `document` / `<html>` 不销毁**，所以：

- 用 `turbo:load` 做每页初始化，不要只靠 `DOMContentLoaded`
- 全局监听器、定时器要自己清理（或交给 Stimulus `connect` / `disconnect`）

常用属性：

```html
<a href="/x" data-turbo="false">整页刷新</a>
<a href="/settings" data-turbo-action="replace">替换历史</a>
<a href="/reports" data-turbo-preload>预载入缓存</a>
<a href="/logout" data-turbo-method="delete" data-turbo-confirm="确定？">退出</a>
```

表单成功后常见 **Redirect → GET 再渲染**；也可直接返回 `text/vnd.turbo-stream.html` 一次更新多处。

## 4. Turbo Frames

```html
<turbo-frame id="new_message">
  <form action="/messages" method="post">…</form>
</turbo-frame>
```

Frame 内导航默认只更新该区域；响应里必须有**同 id** 的 `<turbo-frame>`。

```html
<!-- 懒加载 -->
<turbo-frame id="comments" src="/posts/1/comments" loading="lazy">
  <p>加载中…</p>
</turbo-frame>

<!-- 跳出到整页 -->
<a href="/checkout" data-turbo-frame="_top">去结算</a>
```

| 需求 | 更合适 |
|------|--------|
| 操作只影响一块固定区域 | **Frame** |
| 一次改多处 / 别人推送过来 | **Stream** |
| 懒加载独立区块 | **Frame** + `src` |

## 5. Turbo Streams

```html
<turbo-stream action="append" target="messages">
  <template>
    <div id="message_1">Hello</div>
  </template>
</turbo-stream>
```

| action | 效果 |
|--------|------|
| `append` / `prepend` | 追加 / 前置 |
| `replace` / `update` | 换元素 / 换内部；可加 `method="morph"` |
| `remove` | 删除 |
| `before` / `after` | 插到目标前后 |
| `refresh` | 触发页面刷新 |

传输：表单 HTTP 响应、WebSocket、SSE，或 `Turbo.renderStreamMessage(html)`。

精髓是**复用服务端模板**：列表 partial 首屏用、创建用、广播还用，不必再维护一套客户端模板。Streams **故意不执行随意 JS**——动画与行为交给 Stimulus。

## 6. 事件与 API（高频）

```text
turbo:before-visit → turbo:visit
turbo:before-fetch-request
turbo:before-render → turbo:render → turbo:load
turbo:frame-load / turbo:before-stream-render
```

```js
import * as Turbo from "@hotwired/turbo"

Turbo.visit("/dashboard")
Turbo.cache.clear()
Turbo.renderStreamMessage(streamHtml)
Turbo.config.drive.progressBarDelay = 300
```

## 7. 对照源码怎么读

本地克隆：`~/src/turbo`。

```text
src/core/session.js      # 心脏：Observer + Navigator
src/core/drive/visit.js  # 一次页面访问
src/core/frames/         # Frame 控制器与渲染
src/core/streams/stream_actions.js  # 九种 action，很短必读
src/elements/            # <turbo-frame> / <turbo-stream>
src/observers/           # 链接、表单、预取…
```

建议顺序：入口 `start()` → 点击如何变 `visit` → Frame 同 id 抽取 → `StreamActions` → morph / refresh。

## 8. 易错点

1. 每页初始化写在 `DOMContentLoaded` → 改用 `turbo:load`
2. Frame 响应缺少同 id → 导航失败
3. `<turbo-stream-source>` 挂在会被换掉的 body 深处 → 导航后断连；放持久区域（如 `<head>`）
4. 只做 Stream、不做无 JS 降级 → 实时一挂全站不可用
5. 全局 `addEventListener` 重复绑定 → Stimulus 或先移除

## 9. 延伸阅读

- 站点内分章：[`turbo-notes/`](https://github.com/AriseshineSky/AriseshineSky.github.io/tree/master/turbo-notes)
- 导航页：[/turbo-learning/](/turbo-learning/)
- 官方 Handbook：[Introduction](https://turbo.hotwired.dev/handbook/introduction) · [Drive](https://turbo.hotwired.dev/handbook/drive) · [Frames](https://turbo.hotwired.dev/handbook/frames) · [Streams](https://turbo.hotwired.dev/handbook/streams)
