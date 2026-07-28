# 示例片段

这些是最小 HTML 示意，可粘到任意静态页或服务端模板中验证概念（需已加载 `@hotwired/turbo`）。

## 1. Drive：普通导航

```html
<nav>
  <a href="/">首页</a>
  <a href="/about">关于</a>
  <a href="/legacy" data-turbo="false">强制整页</a>
</nav>
```

## 2. Frame：内联编辑

```html
<turbo-frame id="message_42">
  <p>原文内容</p>
  <a href="/messages/42/edit">编辑</a>
</turbo-frame>

<!-- /messages/42/edit 响应中： -->
<turbo-frame id="message_42">
  <form action="/messages/42" method="post">
    <input type="hidden" name="_method" value="patch">
    <textarea name="content">原文内容</textarea>
    <button>保存</button>
  </form>
</turbo-frame>
```

## 3. Frame：懒加载

```html
<turbo-frame id="comments" src="/posts/1/comments" loading="lazy">
  <p>评论加载中…</p>
</turbo-frame>
```

## 4. Stream：删除一行

```html
<!-- 表单 DELETE 成功后的响应 body -->
<turbo-stream action="remove" target="message_42"></turbo-stream>
```

## 5. Stream：追加消息

```html
<turbo-stream action="append" target="messages">
  <template>
    <div id="message_99">新消息</div>
  </template>
</turbo-stream>
```

## 6. Stream：多处更新

```html
<turbo-stream action="prepend" target="messages">
  <template><div id="message_100">…</div></template>
</turbo-stream>
<turbo-stream action="update" target="unread_count">
  <template>3</template>
</turbo-stream>
```

## 7. 跳出 Frame 整页走

```html
<turbo-frame id="modal">
  <a href="/checkout" data-turbo-frame="_top">去结算</a>
</turbo-frame>
```
