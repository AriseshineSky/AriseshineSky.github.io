# 03 · Turbo Frames

Frames 把页面拆成**独立导航上下文**：Frame 内的链接/表单默认只更新该 Frame，其余页面不动。

## 基本用法

```html
<turbo-frame id="new_message">
  <form action="/messages" method="post">
    <textarea name="content"></textarea>
    <button>发送</button>
  </form>
</turbo-frame>
```

提交后，Turbo 在响应 HTML 里查找 **同 id** 的 `<turbo-frame id="new_message">`，用其内容替换当前 Frame。

> 响应可以是整页，也可以只是带该 Frame 的片段；关键是 **id 必须匹配**。

## 懒加载 / 急切加载

```html
<!-- 进入视口或按策略加载 -->
<turbo-frame id="messages" src="/messages" loading="lazy">
  <p>加载中…</p>
</turbo-frame>

<!-- 立刻请求 -->
<turbo-frame id="sidebar" src="/sidebar" loading="eager">
  <p>加载侧边栏…</p>
</turbo-frame>
```

好处：

1. **独立缓存** —— 侧边栏过期不必让整页缓存失效
2. **并行渲染** —— 骨架先出，多 Frame 并行请求
3. **Native 友好** —— 每个片段自带 URL，可映射到独立原生屏幕

## 导航目标

```html
<!-- 在 Frame 内导航（默认） -->
<turbo-frame id="detail">
  <a href="/items/1">查看</a>
</turbo-frame>

<!-- 打到别的 Frame -->
<a href="/items/1" data-turbo-frame="detail">打开详情</a>

<!-- 打到整页（跳出 Frame） -->
<a href="/items/1" data-turbo-frame="_top">整页打开</a>

<!-- 忽略 Frame，整页 Drive 导航 -->
<a href="/help" data-turbo-frame="_top">帮助</a>
```

## 提升为整页 Visit

Frame 导航默认**不改浏览器 URL**（仍在原页上下文）。若希望 URL 也跟着变：

```html
<a href="/messages/1" data-turbo-action="advance">打开</a>
<!-- 写在 frame 或链接/表单上，值同 Drive：advance | replace | restore -->
```

## 「缺少 Frame」与跳出

若请求期望某个 Frame，但响应里没有对应 id，Turbo 视为错误（可能整页替换或触发错误事件，视版本/场景而定）。常见正确做法：

- 服务端始终包上同 id 的 Frame
- 或显式用 `data-turbo-frame="_top"` / redirect 做整页流

## Morph 刷新 Frame

```html
<turbo-frame id="list" src="/list" refresh="morph">
  …
</turbo-frame>
```

配合页面刷新策略时，用 morph 更新子树，减少闪烁、更好保留状态。

## 暂停渲染

可在 `turbo:before-frame-render` 里拿到 `event.detail.render`，做动画后再调用，实现自定义过渡。

## 何时用 Frame，何时用 Stream

| 需求 | 更合适 |
|------|--------|
| 用户操作只影响一块固定区域 | **Frame** |
| 一次操作要改页面多处 | **Stream** |
| 别人的操作推送到我的页面 | **Stream**（WS/SSE） |
| 懒加载独立区块 | **Frame** `src` |

Frames **不负责**替代 Streams；两者互补。不要仅为了 Stream 而把目标包成无意义的 Frame。

## CSRF

Frame 内表单仍走正常 CSRF；Rails 等框架下 meta/csrf-token 在持久 `<head>` 中通常继续可用。

## 下一步

→ [04-streams.md](./04-streams.md)
