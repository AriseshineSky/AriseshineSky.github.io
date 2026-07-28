# 04 · Turbo Streams

Streams 用声明式 HTML 描述 **DOM 手术**：每个 `<turbo-stream>` 带 `action` + `target`/`targets`，内容放在 `<template>` 里。

## 消息形态

```html
<turbo-stream action="append" target="messages">
  <template>
    <div id="message_1">Hello</div>
  </template>
</turbo-stream>
```

可在**一条消息**里放多个 `<turbo-stream>`。

插入页面的 stream 元素会被处理并移除（页面/Frame 加载时内嵌 stream 也会执行）。

## Actions（对照源码 `StreamActions`）

| action | 效果 |
|--------|------|
| `append` | 追加到目标元素内 |
| `prepend` | 前置到目标元素内 |
| `replace` | 整元素替换；`method="morph"` 则 morph |
| `update` | 清空后填入子内容；`method="morph"` 则 morph 子树 |
| `remove` | 删除目标（忽略 template） |
| `before` | 插到目标之前 |
| `after` | 插到目标之后 |
| `refresh` | 触发页面刷新（可带 `request-id`、`scroll`） |

源码位置概念：`src/core/streams/stream_actions.js`。

### 多目标

```html
<turbo-stream action="remove" targets=".outdated">
</turbo-stream>
```

`target` = 单个 DOM id；`targets` = CSS 选择器。

## 传输方式

### 1. HTTP 表单响应

对 `POST/PUT/PATCH/DELETE`，Turbo 会在 `Accept` 中带上 `text/vnd.turbo-stream.html`。服务端可返回：

```http
Content-Type: text/vnd.turbo-stream.html
```

```html
<turbo-stream action="remove" target="message_1"></turbo-stream>
```

GET 默认不带该 MIME；需要时在链接/表单加 `data-turbo-stream`。

### 2. WebSocket / SSE

```html
<!-- 放在 <head> 或持久区域，避免被 body 替换清掉 -->
<turbo-cable-stream-source ...>  <!-- Rails helper 示例 -->
<!-- 或通用： -->
<turbo-stream-source src="wss://example.com/stream">
</turbo-stream-source>
```

`ws://` / `wss://` → WebSocket；否则 → `EventSource`（SSE）。

### 3. 手动

```js
Turbo.renderStreamMessage(`
  <turbo-stream action="append" target="messages">
    <template><div id="m2">…</div></template>
  </turbo-stream>
`)
```

## 复用服务端模板（精髓）

首屏列表用的 partial，创建/广播时还用同一份：

```ruby
# Rails 示意
render turbo_stream: turbo_stream.append(
  :messages,
  partial: "messages/message",
  locals: { message: message }
)
```

不必再写一套客户端模板。

## 自定义 Action

```js
import { StreamActions } from "@hotwired/turbo"

StreamActions.log = function () {
  console.log(this.getAttribute("message"))
}
```

或监听 `turbo:before-stream-render` 包装 `event.detail.render`。

## 与 Stimulus 分工

Streams **只改 DOM**，不执行随意 JS。动画、焦点、图表初始化 → Stimulus 的 `connect` / 事件。

## 实践清单

1. 先做出无 Stream 的完整 HTML 流程，再叠加 Stream
2. 给可更新节点稳定的 **id**（如 `dom_id`）
3. `replace` vs `update`：要不要换掉根节点（事件监听是否保留）
4. 实时通道挂在 `<head>` 持久区
5. 广播失败时页面仍应可手动刷新可用

## 下一步

→ [05-events-api.md](./05-events-api.md)
