# 01 · 概览与理念

## HTML over the Wire

Turbo 假设：

1. **服务端拥有完整业务真相**（权限、校验、领域模型）
2. **浏览器只负责展示最终 HTML**，不必再维护一套镜像逻辑
3. 需要「应用感」时，用 Drive / Frames / Streams 增强，而不是先上完整前端框架

这不是否定 SPA，而是提供另一条路径：**服务端渲染 + 渐进增强**。

## Hotwire 全家桶

```text
Hotwire
├── Turbo      → 导航与 DOM 更新（本仓库笔记主题）
├── Stimulus   → 小而专的控制器，给 DOM 挂行为
└── (可选) Strada / Native → 原生桥接
```

经验法则：

- **能用 HTML + Turbo 解决的，不要写自定义 fetch + 拼 DOM**
- **需要点击切换、快捷键、局部状态时，用 Stimulus**
- **Streams 故意不做「执行任意 JS」**——行为放在 Stimulus，模板保持可复用

## 与 Turbolinks 的关系

Turbo Drive 是 Turbolinks 的进化：

- 同样：拦截导航、持久化 `window` / `document` / `<html>`，替换 body
- 新增：Frames、Streams、更好的表单流、morph、prefetch 等

若你熟悉 Turbolinks，Drive 几乎「零配置升级」；Frames/Streams 才是新能力。

## 安装与启动

### 浏览器脚本

引入后，库会执行 `Turbo.start()`，挂上各类 Observer（链接、表单、滚动、Stream 等）。

### 模块方式

```js
import * as Turbo from "@hotwired/turbo"

Turbo.visit("/dashboard")           // 编程式访问
Turbo.cache.clear()                 // 清快照缓存
Turbo.renderStreamMessage(html)     // 手动渲染 stream HTML
```

### 后端无关

Turbo **不绑定 Rails**。任何能返回 HTML（以及 `text/vnd.turbo-stream.html`）的后端都能用。Rails 的 `turbo-rails` 只是把广播、helpers、MIME 做得更顺手。

## 心智模型：一次点击发生了什么

以普通同域链接为例（Drive）：

```text
用户点击 <a href="/posts/1">
    → LinkClickObserver 拦截默认跳转
    → History API 更新 URL
    → fetch 拉取 HTML
    → 合并 <head>，替换 <body>
    → 触发 turbo:load 等事件
    → window / 全局 JS 状态保留（注意：不要依赖「整页刷新才清状态」）
```

若点击发生在 `<turbo-frame id="x">` 内：

```text
请求仍发出，但只抽取响应里同 id 的 <turbo-frame>
    → 只替换该 Frame 内容
    → 页面其余部分不动
```

若响应是 Turbo Streams：

```text
Content-Type: text/vnd.turbo-stream.html
    → 解析多个 <turbo-stream>
    → 按 action 对 target 做 append/replace/remove…
```

## 渐进增强原则（官方强烈建议）

1. 先保证 **没有 Turbo 也能用**（完整 HTML 流程、PRGable 表单）
2. 再加 Drive 加速
3. 再加 Frames 分区
4. 最后用 Streams 做多处更新 / 实时

这样 WebSocket 断线、原生 WebView、爬虫、无 JS 降级都更稳。

## 下一步

→ [02-drive.md](./02-drive.md)
