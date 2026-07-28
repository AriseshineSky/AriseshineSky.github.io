# 06 · 源码阅读地图

对照官方仓库 [`hotwired/turbo`](https://github.com/hotwired/turbo) 的 `src/`（笔记整理时版本约 **8.0.23**）。

## 目录鸟瞰

```text
src/
├── index.js                 # 入口：polyfill、elements、Turbo.start()
├── util.js                  # dispatch、busy、URL 小工具
├── core/
│   ├── index.js             # 对外 API：visit、cache、stream、morph…
│   ├── session.js           # 心脏：组装 Observer + Navigator + History
│   ├── cache.js / snapshot.js / view.js / renderer.js
│   ├── morphing.js          # idiomorph 封装
│   ├── drive/               # 整页 Visit、表单、预取、进度条、渲染
│   ├── frames/              # Frame 控制器、渲染、重定向
│   ├── streams/             # StreamMessage、StreamActions、渲染
│   ├── config/              # drive / forms 配置
│   └── native/              # BrowserAdapter
├── elements/
│   ├── frame_element.js     # <turbo-frame>
│   ├── stream_element.js    # <turbo-stream>
│   └── stream_source_element.js
├── http/                    # FetchRequest / FetchResponse
├── observers/               # 点击、表单、预取、滚动、stream、缓存…
└── tests/                   # Playwright / web-test-runner
```

## 建议阅读顺序

### 第 1 天：启动链路

1. `src/index.js` → `Turbo.start()`
2. `core/session.js` → `start()` 里启动了哪些 Observer
3. `observers/link_click_observer.js`、`form_submit_observer.js`

问自己：一次点击如何变成 `session.visit`？

### 第 2 天：Drive Visit

1. `core/drive/navigator.js`
2. `core/drive/visit.js`
3. `core/drive/page_renderer.js` / `page_snapshot.js`
4. `http/fetch_request.js`

问自己：快照缓存何时读写？`advance` / `restore` 差在哪？

### 第 3 天：Frames

1. `elements/frame_element.js`
2. `core/frames/frame_controller.js`
3. `core/frames/frame_renderer.js`
4. `core/frames/frame_redirector.js`

问自己：同 id 抽取如何发生？`_top` 如何跳出？

### 第 4 天：Streams

1. `elements/stream_element.js`
2. `core/streams/stream_actions.js`（九种 action 的实现极短，必读）
3. `core/streams/stream_message.js` / `stream_message_renderer.js`
4. `observers/stream_observer.js`

### 第 5 天：Morph 与刷新

1. `core/morphing.js`
2. `drive/morphing_page_renderer.js`
3. `frames/morphing_frame_renderer.js`
4. StreamActions 里的 `refresh` / `method === "morph"`

## 调试技巧

```bash
cd ~/src/turbo   # 你的官方克隆
yarn install
yarn build
yarn start       # 测试服务器
yarn test:browser
```

在浏览器里：

```js
window.Turbo
document.querySelector("turbo-frame")
```

对关键路径下断点：`Visit#start`、`FrameController#loadSourceURL`、`StreamElement#performAction`。

## 和笔记其它章节的映射

| 概念 | 源码 |
|------|------|
| Drive | `core/drive/*` + link/form observers |
| Frames | `elements/frame_element.js` + `core/frames/*` |
| Streams | `stream_actions.js` + stream elements |
| API | `core/index.js` |
| 配置 | `core/config/*` |

## 下一步

→ [07-cheatsheet.md](./07-cheatsheet.md)
