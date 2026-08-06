---
title: "Bootsnap 启动优化原理分析"
date: 2026-08-06 17:00:00 -0500
categories: [Ruby, Rails]
tags: [bootsnap, ruby, rails, startup, performance, cache]
description: >-
  结合 rails/bootsnap 源码，拆解 LoadPathCache 与 CompileCache 两大子系统：
  路径预扫描如何把 2×$LOAD_PATH 次 open 降为一次查表，以及 ISeq / YAML / JSON
  编译缓存如何跳过重复解析与编译。
---

> 项目地址：[rails/bootsnap](https://github.com/rails/bootsnap)。实测效果：Discourse 启动时间减少约 50%（6s → 3s）；Shopify 核心应用减少约 75%（25s → 6.5s），其中约 75% 来自路径缓存、约 25% 来自编译缓存。

Bootsnap 不改变 Ruby 语义，而是在几个关键的运行时 hook 点插入「结果缓存」层，用一次性扫描 / 编译换取后续启动时的直接读取。整体分为两大子系统：**路径预扫描缓存（LoadPathCache）** 与 **编译结果缓存（CompileCache）**。

## 目录

1. [路径预扫描缓存](#1-路径预扫描缓存path-pre-scanning)
2. [编译结果缓存](#2-编译结果缓存compilation-caching)
3. [两个子系统的关系](#3-两个子系统的关系与整体效果)
4. [工程上的补充设计](#4-工程上的补充设计)

---

## 1. 路径预扫描缓存（Path Pre-Scanning）

### 1.1 要解决的问题

Ruby 原生的 `Kernel#require` 逻辑是：遍历 `$LOAD_PATH` 里的每一个目录，依次尝试 `目录/foo.rb`，再尝试 `目录/foo.<动态库后缀>`（`.so` / `.bundle` 等），任何一次 `open` 成功就停止；如果所有目录都试过还是没找到，就抛出 `LoadError`。

由于每个目录都要尝试两种后缀（`.rb` 和动态库后缀），Shopify 官方工程博客明确指出：*The coefficient of 2 is due to scanning for both 'something.rb' and 'something.bundle' for native extensions*——也就是为什么最坏情况下是 `2 * $LOAD_PATH.length` 次文件系统访问。

### 1.2 Bootsnap 的实现方式

**关键文件：`lib/bootsnap/load_path_cache/core_ext/kernel_require.rb`**

Bootsnap 用 Ruby 的 `alias_method` 技巧整体替换了 `Kernel#require`：

```ruby
module Kernel
  alias_method :require_without_bootsnap, :require
  alias_method :require, :require # 避免方法重定义警告

  def require(path)
    return require_without_bootsnap(path) unless Bootsnap::LoadPathCache.enabled?

    string_path = Bootsnap.rb_get_path(path)
    return false if Bootsnap::LoadPathCache.loaded_features_index.key?(string_path)

    resolved = Bootsnap::LoadPathCache.load_path_cache.find(string_path)
    # FALLBACK_SCAN → 回退原生扫描
    # false         → 内建 feature，视为已加载
    # nil           → 索引未命中
    # 绝对路径      → 直接 require 一次 open
    ...
  end

  private :require
end
```

新版本的 `require` 会先查 `loaded_features_index`（避免重复加载），然后调用 `load_path_cache.find(string_path)` 去查缓存索引；命中后拿到解析好的绝对路径，再 `require_without_bootsnap(resolved)`，只触发**一次** `open`，不再逐目录、逐后缀尝试。

**关键文件：`lib/bootsnap/load_path_cache/cache.rb`（`Cache#find` / `Cache#search_index`）**

真正的查找逻辑在 `Cache` 类里。核心方法 `find(feature)`：

```ruby
def find(feature)
  ...
  x = search_index(feature)
  return x if x
  return false if BUILTIN_FEATURES.key?(feature)

  case File.extname(feature)
  when "", *CACHED_EXTENSIONS
    nil   # 明确找不到（缓存管理范围内的扩展名）
  when DOT_SO
    ...   # 处理 .so / .bundle 互换
  else
    return FALLBACK_SCAN  # 未缓存扩展名（如 .rake），回退原生扫描
  end
end
```

以及内部的 `search_index`：把一次 `require` 拆成对 `.rb`、平台动态库后缀（`DLEXT` / `DLEXT2`）的**索引查表**，而不是文件系统 `open`：

```ruby
def search_index(feature)
  try_index(feature + DOT_RB) ||
    try_index(feature + DLEXT) ||
    try_index(feature + DLEXT2) ||
    try_index(feature)
end
```

`try_index` 只是查一个内存 Hash（`@index[feature]`），命中就直接返回拼接好的绝对路径，完全不涉及磁盘 I/O。

**索引从哪来：`lib/bootsnap/load_path_cache/path_scanner.rb`**

`PathScanner` 负责真正的目录扫描（`walk` 遍历目录树），把每个目录下所有以 `REQUIRABLE_EXTENSIONS`（`.rb` + 动态库后缀）结尾的文件路径收集起来，构建成上面 `Cache` 用的索引。扫描结果会持久化到磁盘缓存（`@store`）；下次进程启动直接反序列化加载，不必重新走文件系统。

### 1.3 stable / volatile 目录分类与 30 秒过期窗口

README 把 `$LOAD_PATH` 条目分成两类，实现落在 `lib/bootsnap/load_path_cache/path.rb`：

| 类型 | 判定范围 | 失效策略 |
|------|----------|----------|
| **stable** | Ruby 安装前缀、`Gem.path`、`Bundler.bundle_path` | 扫描一次后长期信任，不因 mtime 自动失效 |
| **volatile** | 其余目录（应用代码等） | 用目录树 mtime 判断是否需要重新扫描 |

另外，`Cache` 在 `development_mode` 下还有一层整表过期：

```ruby
class Cache
  AGE_THRESHOLD = 30 # seconds

  def stale?
    @development_mode && @generated_at + AGE_THRESHOLD < now
  end
end
```

超过 30 秒会 `reinitialize` 整份索引。生产环境关闭这层窗口，追求极致启动性能；开发环境则兼顾「及时发现新文件」。两者叠加：stable / volatile 控制**单个目录**何时重扫，`AGE_THRESHOLD` 控制**开发模式下整表**何时重建。

### 1.4 对 `LoadError` 场景的优化

未命中时，若扩展名属于 Bootsnap 明确缓存管理的类型（`.rb`、`.so`、`.bundle` 等），`find` 返回 `nil`，不再对 `$LOAD_PATH` 做「全量后缀枚举式」扫描。README 强调：*Bootsnap caches this result too, raising a LoadError without touching the filesystem at all*——负向结果同样被缓存，避免 `2 * $LOAD_PATH.length` 次无意义 `open`。开发模式下索引未命中会退回 `FALLBACK_SCAN`，以便发现刚创建的文件。

---

## 2. 编译结果缓存（Compilation Caching）

### 2.1 Ruby 字节码缓存（ISeq Cache）

**要解决的问题**：Ruby 源码执行前必须先编译成内部字节码（`RubyVM::InstructionSequence`），这个编译过程有实际开销；正常情况下每次进程启动都要重新编译一遍所有被加载的 `.rb` 文件。

**关键文件：`lib/bootsnap/compile_cache/iseq.rb`**

Bootsnap 覆盖了 Ruby VM 提供的 `RubyVM::InstructionSequence.load_iseq` 钩子（`InstructionSequenceMixin#load_iseq`）：

```ruby
module InstructionSequenceMixin
  def load_iseq(path)
    Bootsnap::CompileCache::ISeq.fetch(path.to_s)
  rescue RuntimeError => error
    ...
    raise
  end
end
```

配套的 `input_to_storage` / `storage_to_output` 定义了缓存内容的生成与复原方式：

```ruby
def input_to_storage(_, path)
  RubyVM::InstructionSequence.compile_file(path, @compile_options).to_binary
rescue SyntaxError
  UNCOMPILABLE # 语法错误，不缓存
end

def storage_to_output(binary, _args)
  iseq = RubyVM::InstructionSequence.load_from_binary(binary)
  binary.clear
  iseq
rescue RuntimeError => error
  ...
end
```

第一次加载某个 `.rb` 文件时正常编译一次，再用 `to_binary` 把字节码序列化写入缓存目录；之后加载同一文件时，只要缓存有效，直接 `load_from_binary` 反序列化，跳过语法解析和编译。开启 Coverage 时无法使用 iseq dump/load，会按条件跳过或走自定义 compiler。

### 2.2 YAML / JSON 反序列化缓存

原理与 ISeq 缓存一致，只是缓存对象换成 YAML / JSON 解析后的 Ruby 对象。Bootsnap hook 了 `YAML.load_file` 和 `JSON.load_file`，把解析结果序列化为 MessagePack（遇到不支持的类型则退化为 Marshal）写入缓存；下次加载同一文件直接从 MessagePack / Marshal 反序列化，省去文本解析开销。官方 README 明确指出：MessagePack 与 Marshal 的反序列化速度远快于 YAML / JSON 解析。

### 2.3 缓存有效性：32 字节 Cache Key

每个缓存文件带有一个 32 字节头部作为缓存键，包含：

| 字段 | 含义 |
|------|------|
| `ruby_version_digest` | `RUBY_DESCRIPTION` + Bootsnap schema 版本 + `RubyVM::InstructionSequence.compile_option` 的摘要 |
| `size` | 源文件大小 |
| `digest` | 源文件内容的 FNV1a-64 哈希 |
| `mtime` | 源文件编译时的最后修改时间 |
| `data_size` | 缓存内容的字节数 |

字段全部匹配则直接复用；任意一项不匹配（文件改了、Ruby 版本换了、编译选项变了）就重新编译并覆盖旧缓存。既保证正确性，又避免每次整文件比对。

---

## 3. 两个子系统的关系与整体效果

| 子系统 | 优化对象 | 核心 Hook 点 | Shopify 案例贡献占比 |
|--------|----------|--------------|----------------------|
| LoadPathCache | `$LOAD_PATH` 遍历、`require` / `load` 的文件定位 | `Kernel#require`、`Kernel#load` | 约 75% |
| CompileCache::ISeq | Ruby 源码 → 字节码的编译过程 | `RubyVM::InstructionSequence.load_iseq` | 约 25%（与 YAML / JSON 合计） |
| CompileCache::YAML / JSON | YAML / JSON 文本解析 | `YAML.load_file`、`JSON.load_file` | 包含在上面 25% 内 |

两者正交、互补：LoadPathCache 解决「找文件」的开销，CompileCache 解决「读懂文件内容」的开销。合在一起，覆盖了 Ruby 应用启动阶段两类最主要的重复性开销。

---

## 4. 工程上的补充设计

- **precompile 命令**：生产部署（如 Docker 镜像构建）可用 `bootsnap precompile` 提前生成 ISeq / YAML 缓存，避免线上首次请求才触发编译。对 immutable / 只读运行时尤其重要。

  ```bash
  bundle exec bootsnap precompile --gemfile app/ lib/ config/
  ```

- **自定义编译器（Custom Compilers）**：可替换默认编译逻辑，例如只对应用自身代码（而非 gem）开启 `frozen_string_literal: true`，在 `config/bootsnap.rb` 里通过 `compiler_selector` 配置：

  ```ruby
  Bootsnap.enable_frozen_string_literal(app_only: true)
  ```

- **缓存不会自动清理**：README 明确警告 Bootsnap 从不清理自己的缓存目录。长期运行 / 频繁部署需自行定期清理 `tmp/cache/bootsnap*`，否则缓存持续膨胀会拖慢部署或读取。

- **本地文件系统依赖**：缓存目录必须在快速的本地文件系统上；放在网络挂载盘反而会显著拖慢应用。

- **与 Spring 正交**：Bootsnap 加速单文件加载；Spring 常驻预启动进程以跳过部分 boot。两者可同时使用。

---

## 参考源码路径（rails/bootsnap，main 分支）

- `lib/bootsnap/load_path_cache/core_ext/kernel_require.rb` — `require` / `load` 的方法替换入口
- `lib/bootsnap/load_path_cache/cache.rb` — 索引查找核心逻辑（`find`、`search_index`、`AGE_THRESHOLD`）
- `lib/bootsnap/load_path_cache/path.rb` — stable / volatile 分类与按目录的缓存失效
- `lib/bootsnap/load_path_cache/path_scanner.rb` — 目录扫描、可 require 文件的收集
- `lib/bootsnap/compile_cache/iseq.rb` — ISeq 字节码缓存的 hook 与序列化逻辑
- `README.md` — 整体设计说明、性能数据、Cache Key 结构说明
