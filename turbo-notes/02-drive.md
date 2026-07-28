# 02 · Turbo Drive

Drive 负责**页面级导航**：同域链接点击与表单提交变成后台 `fetch`，再更新页面，避免整页卸载。

## 基本行为

| 场景 | Drive 做什么 |
|------|----------------|
| 同域 `<a>` | 拦截 → History → fetch → 渲染 |
| 表单 submit | 变成 fetch；跟随 redirect；渲染 HTML |
| 渲染 | 替换 `<body>` 内容，合并 `<head>` |
| 持久化 | `window`、`document`、`<html>` 不销毁 |

跨域链接、带 `target`、下载链接、`data-turbo="false"` 等通常走浏览器默认行为。

## Visit 类型

| action | 含义 |
|--------|------|
| `advance` | 默认，压入历史记录（像正常前进） |
| `replace` | 替换当前历史条目 |
| `restore` | 后退/前进恢复（常配合缓存快照） |

```html
<a href="/settings" data-turbo-action="replace">设置</a>
```

## 常用 data 属性

```html
<!-- 关闭某段的 Turbo -->
<div data-turbo="false">
  <a href="/full-reload">强制整页</a>
</div>

<!-- 单链接关闭 -->
<a href="/x" data-turbo="false">…</a>

<!-- 确认框（表单/方法链接） -->
<button data-turbo-confirm="确定删除？">删除</button>

<!-- 非 GET 链接（需配合） -->
<a href="/logout" data-turbo-method="delete">退出</a>

<!-- 预加载到缓存 -->
<a href="/reports" data-turbo-preload>报表</a>

<!-- GET 也要接受 Stream MIME -->
<a href="/notifications" data-turbo-stream>通知</a>
```

## 表单

1. Drive 把提交变为 `fetch`
2. 成功后常见模式：**Redirect → 再 GET 渲染**（Post/Redirect/Get）
3. 也可直接返回 **Turbo Streams**（`Content-Type: text/vnd.turbo-stream.html`），一次更新多处 DOM，且可不改 URL

```html
<form action="/messages" method="post">
  <!-- 默认 Turbo 会处理 -->
</form>

<form action="/search" method="get" data-turbo-frame="results">
  <!-- GET 结果渲到指定 Frame，可选 data-turbo-action 更新 URL -->
</form>
```

### 表单模式配置

```js
Turbo.config.forms.mode = "on"       // 默认，增强表单
Turbo.config.forms.mode = "optin"    // 仅 data-turbo=true 的表单
Turbo.config.forms.mode = "off"      // 关闭表单增强
```

## 缓存与预取

- Drive 会把访问过的页面存为 **Snapshot**，前进/后退可瞬间恢复
- `data-turbo-preload`：提前把链接页放入缓存（有若干限制：非跨域、非 frame 驱动链接等）
- Prefetch：悬停/可见时预取（可用 `data-turbo-prefetch="false"` 关闭）

```js
Turbo.cache.clear()
// 或不缓存某一页：响应头 / meta
```

```html
<meta name="turbo-cache-control" content="no-cache">
```

## 进度条

默认约 500ms 后显示顶部进度条：

```js
Turbo.config.drive.progressBarDelay = 300
```

## 页面刷新与 Morph（Turbo 8）

除了「整 body 替换」，还可用 **morph**（基于 idiomorph）做更细的 DOM 差分更新，利于保留焦点、输入状态等。

常见触发：

- Stream `action="refresh"`
- `method="morph"` 的 replace/update
- 页面/Frame 配置 `refresh="morph"`

## Drive 生命周期（简）

```text
turbo:click
turbo:before-visit → turbo:visit
turbo:before-fetch-request → turbo:before-fetch-response
turbo:before-cache
turbo:before-render → turbo:render
turbo:load
```

取消导航：在 `turbo:before-visit` 里 `event.preventDefault()`。

## 实践注意

1. **全局 JS 状态会跨页保留** —— 单例监听器、定时器要自己清理，或挂在 Stimulus connect/disconnect
2. `DOMContentLoaded` **只在首屏触发一次**；之后用 `turbo:load` / `turbo:render`
3. 第三方脚本若假设「每次都是全新 document」，可能需要适配
4. 需要完整文档重载时用 `data-turbo="false"` 或 `Turbo.visit(url, { action: "replace" })` 等明确策略

## 下一步

→ [03-frames.md](./03-frames.md)
