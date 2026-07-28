# 05 · 事件与 JS API

## 常用事件

### Drive / 页面

| 事件 | 时机 |
|------|------|
| `turbo:click` | 链接被拦截前 |
| `turbo:before-visit` | 访问开始前（可 `preventDefault`） |
| `turbo:visit` | 访问开始 |
| `turbo:before-fetch-request` | 发出 fetch 前（可改 `fetchOptions`） |
| `turbo:before-fetch-response` | 收到响应后、处理前 |
| `turbo:submit-start` / `turbo:submit-end` | 表单提交生命周期 |
| `turbo:before-cache` | 当前页快照写入缓存前 |
| `turbo:before-render` | 渲染前（可自定义 `render`） |
| `turbo:render` | 渲染完成 |
| `turbo:load` | 页面就绪（含恢复缓存） |
| `turbo:frame-load` | Frame 加载完成 |
| `turbo:frame-render` | Frame 渲染 |
| `turbo:before-frame-render` | Frame 渲染前 |
| `turbo:before-stream-render` | Stream 渲染前 |
| `turbo:morph` 等 | Morph 相关 |
| `turbo:fetch-request-error` | 请求失败 |

### 示例：改请求头

```js
document.addEventListener("turbo:before-fetch-request", (event) => {
  event.detail.fetchOptions.headers["X-Custom"] = "1"
})
```

### 示例：首屏后初始化

```js
document.addEventListener("DOMContentLoaded", initOnce) // 仅一次
document.addEventListener("turbo:load", initEveryPage)  // 每次导航
```

## 主要 API（`src/core/index.js`）

```js
import * as Turbo from "@hotwired/turbo"

Turbo.start()
Turbo.visit("/path", { action: "advance", frame: "sidebar" })
Turbo.connectStreamSource(source)
Turbo.disconnectStreamSource(source)
Turbo.renderStreamMessage(html)
Turbo.cache.clear()
Turbo.navigator   // 会话导航器
Turbo.session
Turbo.config.drive.progressBarDelay = 400
Turbo.config.forms.confirm = (message) => myConfirm(message)
Turbo.StreamActions.myAction = function () { /* … */ }
```

Morph 辅助：

```js
Turbo.morphBodyElements(currentBody, newBody)
Turbo.morphTurboFrameElements(currentFrame, newFrame)
```

## 适配器（Native）

`Turbo.registerAdapter(adapter)` 供 iOS/Android 壳接管进度条、访问提议等；浏览器默认是 `BrowserAdapter`。

## 下一步

→ [06-source-map.md](./06-source-map.md)
