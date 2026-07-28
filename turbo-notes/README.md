# Hotwired Turbo 学习笔记

基于官方仓库 [`hotwired/turbo`](https://github.com/hotwired/turbo)（对照 `@hotwired/turbo` **8.0.x**）与 [Turbo Handbook](https://turbo.hotwired.dev/handbook/introduction) 整理。

> 核心理念：**HTML over the Wire** —— 服务端直接返回 HTML，浏览器用 Turbo 做局部/整页更新，尽量少写自定义前端 JS。

博客导读：[Hotwired Turbo 学习总结](/posts/hotwired-turbo-learning/)

## 目录

| 文档 | 内容 |
|------|------|
| [01-overview.md](./01-overview.md) | 理念、安装、与 Hotwire/Stimulus 关系 |
| [02-drive.md](./02-drive.md) | Drive 导航、表单、缓存、预取、常用 data 属性 |
| [03-frames.md](./03-frames.md) | Frames 作用域、懒加载、跳出 Frame、morph |
| [04-streams.md](./04-streams.md) | Streams 九种 action、HTTP/WS/SSE、自定义 action |
| [05-events-api.md](./05-events-api.md) | 生命周期事件与 JS API |
| [06-source-map.md](./06-source-map.md) | 对照 `hotwired/turbo` 源码目录阅读地图 |
| [07-cheatsheet.md](./07-cheatsheet.md) | 速查表 |
| [examples/snippets.md](./examples/snippets.md) | 最小 HTML 片段示例 |

## 推荐学习路径

1. 概览 → Drive「免费加速」
2. Frame：点击编辑 → 同区域变表单
3. Stream：删除后 `remove` / 创建后 `append`
4. 对照本地 `~/src/turbo` 读 `Session` / `Visit` / `StreamActions`
5. 需要细粒度 DOM 行为时再学 [Stimulus](https://stimulus.hotwired.dev)

## 官方资源

- Handbook：https://turbo.hotwired.dev/handbook/introduction
- 源码：https://github.com/hotwired/turbo
- turbo-rails：https://github.com/hotwired/turbo-rails
