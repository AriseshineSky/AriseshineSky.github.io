---
layout: post
title: Standard Directory Layout
categories: [project]
description: Standard Directory Layout
keywords: maven, directory
mermaid: false
sequence: false
flow: false
mathjax: false
mindmap: false
mindmap2: false
---
# Code Review Cases

出于性能考虑，我的程序里把数据库里的对象全部加载到本地缓存，用 map 来存储。问题是：如果有人修改了 map 里缓存的对象怎么办？
map 用到了 google 的 Guava 库里的不可变 map
被缓存的对象应该做到不可变，即该对象只有 get 方法，不能有 set 方法，对象的所有属性都用 final 修饰
