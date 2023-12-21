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

## 1. 被缓存的对象应该做到不可变
出于性能考虑，我的程序里把数据库里的对象全部加载到本地缓存，用 map 来存储。问题是：如果有人修改了 map 里缓存的对象怎么办？
map 用到了 google 的 Guava 库里的不可变 map
被缓存的对象应该做到不可变，即该对象只有 get 方法，不能有 set 方法，对象的所有属性都用 final 修饰

## 2. 调用远程接口时如果失败，有无重试机制，是怎样的重试机制
订单支付回调的业务，第三方支付在用户完成支付以后，回调我方的通知接口，我方再执行订单状态修改、发货等后续业务
问题：在第三方支付回调我方通知接口时，我方的接口可能会返回失败，这样可能导致死循环
修改建议是先返回成功，订单状态修改和发货等操作异步处理
