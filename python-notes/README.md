# Python 笔记

以 CPython 标准库源码为素材，整理 Python 语言特性、惯用法与设计模式。

## 目录

| 主题 | 文件 | 源码示例 |
|------|------|----------|
| `__` 双下划线命名全解 | [01-dunder-and-underscore.md](01-dunder-and-underscore.md) | `Lib/heapq.py` |

## 约定

- 示例代码优先引用 CPython `Lib/` 中的真实实现
- 区分「语言机制」与「社区惯例」——前者有运行时行为，后者只是约定
- 后续可扩展：描述符、迭代器协议、模块导入、`dataclass` 等
