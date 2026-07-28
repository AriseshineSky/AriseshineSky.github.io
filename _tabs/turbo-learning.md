---
icon: fas fa-bolt
order: 3
---

# Turbo 学习笔记

阅读 [hotwired/turbo](https://github.com/hotwired/turbo) 与 [Turbo Handbook](https://turbo.hotwired.dev/handbook/introduction) 时的中文总结，对照本地源码 `~/src/turbo`（约 8.0.x）。

## 导读

- [Hotwired Turbo 学习总结](/posts/hotwired-turbo-learning/) — Drive / Frames / Streams 总览与选型

## 分章笔记（仓库内）

源文件在站点仓库 [`turbo-notes/`](https://github.com/AriseshineSky/AriseshineSky.github.io/tree/master/turbo-notes)：

1. [概览与理念](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/turbo-notes/01-overview.md)
2. [Turbo Drive](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/turbo-notes/02-drive.md)
3. [Turbo Frames](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/turbo-notes/03-frames.md)
4. [Turbo Streams](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/turbo-notes/04-streams.md)
5. [事件与 JS API](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/turbo-notes/05-events-api.md)
6. [源码阅读地图](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/turbo-notes/06-source-map.md)
7. [速查表](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/turbo-notes/07-cheatsheet.md)
8. [示例片段](https://github.com/AriseshineSky/AriseshineSky.github.io/blob/master/turbo-notes/examples/snippets.md)

## 推荐阅读顺序

1. 导读博文建立心智模型
2. Drive → Frames → Streams
3. 用速查表复习 data 属性与 stream actions
4. 按源码地图读 `Session` / `Visit` / `StreamActions`
