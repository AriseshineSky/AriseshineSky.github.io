# Python 中 `__` 命名全解：以 heapq.py 为例

> 源码参考：CPython `Lib/heapq.py`

Python 里带下划线的名字容易混为一谈。`heapq.py` 恰好把几种典型用法都集中在一起，适合作为入门样本。

## 一张总览表

| 形式 | 示例（heapq.py） | 性质 | 作用 |
|------|------------------|------|------|
| `__xxx__`（两侧都有） | `__all__`、`__name__`、`__next__` | **语言机制** | 特殊方法、模块钩子、内置协议 |
| `__xxx`（仅前缀） | 类成员如 `__value` | **名称改写** | 仅在类定义内生效，防子类意外覆盖 |
| `_xxx`（单下划线） | `_siftdown`、`_heapify` | **惯例** | 表示「内部实现，请勿依赖」 |
| `xxx_`（单后缀） | （heapq 中未出现） | **惯例** | 避免与关键字冲突，如 `class_` |

下面按 heapq 里出现的顺序逐一说明。

---

## 1. 模块级 `__all__`：控制 `from module import *`

```python
__all__ = ['heappush', 'heappop', 'heapify', 'heapreplace', 'heappushpop',
           'heappush_max', 'heappop_max', 'heapify_max', 'heapreplace_max',
           'heappushpop_max', 'nlargest', 'nsmallest', 'merge']
```

**机制**：执行 `from heapq import *` 时，只有列在 `__all__` 里的名字会被导入。

**为什么需要它**：heapq 内部还有 `_siftdown`、`_siftup` 等辅助函数，以及从 C 扩展 `_heapq` 导入的符号。没有 `__all__` 的话，`import *` 可能把实现细节一并暴露出去。

**注意**：`__all__` 只影响 `import *`，不影响 `import heapq` 或 `from heapq import heappush`。

---

## 2. 模块级 `__about__`：供文档工具读取的说明

```python
__about__ = """Heap queues

[explanation by François Pinard]
...
"""
```

**惯例**：不是语言强制规定的名字，但 `pydoc` 等工具会查找它，作为模块的补充说明。

**与模块 docstring 的区别**：`heapq.py` 顶部已有三引号 docstring（第 1–31 行），`__about__` 则是更长的背景资料。两者可以并存——短 docstring 给 `help(heapq)`，长 `__about__` 给深入阅读。

---

## 3. 单下划线 `_xxx`：内部实现（惯例，非强制）

heapq 把核心堆操作藏在以下划线开头的函数里：

```python
def _siftdown(heap, startpos, pos):
    ...

def _siftup(heap, pos):
    ...
```

公开 API `heappush` / `heappop` 调用它们：

```python
def heappush(heap, item):
    heap.append(item)
    _siftdown(heap, 0, len(heap)-1)
```

**含义**：单前导下划线是 **PEP 8 约定的「内部使用」标记**，解释器不会阻止外部访问 `heapq._siftdown`，但文档和类型存根通常不把它当作公共 API。

**函数内的单下划线别名**（性能优化惯用法）：

```python
# merge() 内部
_heapify = heapify
_heappop = heappop
_heapreplace = heapreplace

# 热循环里少做一次全局名字查找
_heapify(h)
_heappop(h)
```

把全局函数绑定到局部变量，在循环密集代码里可减少属性查找开销。名字仍带 `_` 前缀，表示「本函数内部的实现细节」。

---

## 4. `__next__`：迭代器协议（双下划线 = 特殊方法）

```python
# merge() 中
next = it.__next__
h_append([next(), order * direction, next])
```

**机制**：任何迭代器都必须实现 `__next__()`。`for x in it` 和 `next(it)` 最终都调用它；耗尽时抛出 `StopIteration`。

**为什么写成 `it.__next__`**：这里把方法引用存进列表，之后在堆元素里反复调用 `next()`，而不每次走 `next(it)` 的额外封装。直接绑定方法对象是标准库里的常见微优化。

**相关协议**：

| 方法 | 协议 |
|------|------|
| `__iter__` | 返回迭代器自身或可迭代对象 |
| `__next__` | 返回下一个元素 |
| `__len__` | `len()` |
| `__getitem__` | `obj[key]` |

带两侧双下划线的名字统称 **dunder**（double underscore）或 **魔法方法**。

---

## 5. `next.__self__`：绑定方法的底层对象

```python
yield from next.__self__
```

当 `next = it.__next__` 时，`next` 是一个 **绑定方法**（bound method）。`next.__self__` 指向绑定的那个迭代器对象 `it`。

**使用场景**：迭代器已耗尽、堆中只剩最后一个流时，不必再走堆合并逻辑，直接 `yield from` 剩余迭代器，更高效。

**相关属性**：

| 属性 | 含义 |
|------|------|
| `__self__` | 方法绑定的实例 |
| `__func__` | 底层的原始函数对象 |

---

## 6. `if __name__ == "__main__"`：脚本入口

```python
if __name__ == "__main__":
    import doctest
    print(doctest.testmod())
```

**机制**：

- 直接运行 `python heapq.py` 时，`__name__` 为 `"__main__"`，会执行 doctest。
- 被 `import heapq` 时，`__name__` 为 `"heapq"`，这段代码 **不会** 运行。

这是把「模块」与「可执行脚本」二合一的标准写法。

---

## 7. heapq 未展示、但必须区分的：`__xxx` 名称改写

heapq 是模块级函数集合，没有类，因此看不到 **双下划线前缀（无后缀）** 的名称改写（name mangling）。这在自定义类里很常见：

```python
class Parent:
    def __init__(self):
        self.__value = 42   # 实际存储为 _Parent__value

class Child(Parent):
    def show(self):
        print(self.__value)  # 报错！查找的是 _Child__value，不存在
```

**机制**：类体内以 `__` 开头、且不以 `__` 结尾的属性名，会被改写成 `_ClassName__attr`，主要防止子类无意覆盖父类的「私有」字段。

**与单下划线的区别**：

| | 单 `_` | 双 `__` 前缀 |
|--|--------|--------------|
| 作用域 | 模块/类，仅惯例 | 仅类定义体内，解释器改写名字 |
| 子类可见性 | 可见 | 子类用 `__attr` 访问的是另一个名字 |
| 模块函数 | `_siftdown` 这样用 | 不适用于模块级函数 |

---

## 8. `from _heapq import *`：C 扩展与命名

```python
try:
    from _heapq import *
except ImportError:
    pass
```

`_heapq` 是带单下划线的 **C 加速模块**。单下划线表示「实现细节」；导入失败时静默回退到上面的纯 Python 实现。

导入后，若 C 版本提供了同名函数，会覆盖 Python 版——对用户透明，API 不变。

---

## 心智模型：读源码时如何分类

```
看到带下划线的名字
        │
        ├─ 两侧都有 __ ？ ──→ 查「特殊方法 / 模块钩子」表
        │       ├─ __all__, __name__, __doc__  → 模块
        │       ├─ __init__, __repr__          → 类
        │       └─ __next__, __iter__          → 协议
        │
        ├─ 仅前缀 __（在类里）？ ──→ 名称改写，实际是 _ClassName__attr
        │
        └─ 单前缀 _ ？ ──→ 内部实现，别当公共 API
```

---

## heapq 速查：文件中所有「下划线相关」符号

| 符号 | 类型 | 可见性 |
|------|------|--------|
| `__about__` | 模块元数据 | 可访问，非 `__all__` 成员 |
| `__all__` | 导入控制 | 模块属性 |
| `_siftdown`, `_siftup`, `_siftdown_max`, `_siftup_max` | 内部函数 | 可 import，但不承诺稳定 |
| `_heapify`, `_heappop`, …（局部别名） | 函数内局部变量 | 仅函数内 |
| `it.__next__` | 迭代器协议 | 标准 dunder |
| `next.__self__` | 绑定方法属性 | 标准属性 |
| `__name__`, `__main__` | 模块执行入口 | 每个模块都有 |
| `_heapq` | C 扩展模块 | 实现细节 |

---

## 延伸阅读

- [PEP 8 – Naming Conventions](https://peps.python.org/pep-0008/#naming-conventions)
- [Python Data Model – Special method names](https://docs.python.org/3/reference/datamodel.html#special-method-names)
- 本系列下一篇可写：`heapq` 中的算法与 `_siftdown` / `_siftup` 分工
