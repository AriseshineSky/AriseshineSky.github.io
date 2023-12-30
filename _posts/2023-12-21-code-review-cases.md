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


```java
private String fetchUri(AppngHttpGetRequest httpGetRequest) {
    if (!(StringUtil.equals(dbMode, "dev") || StringUtil.equals(dbMode, "test"))) {
        if (httpGetRequest.getUri().startsWith("http://")) {
            return httpGetRequest.getUri().replaceFirst("^http", "https");
        }
    }
    return httpGetRequest.getUri();
}
```
生产环境为什么不能得到正确的https，什么情况触发，多大概率。生产环境得不到正确的schema是个异常case
http 替换成 https，但是中间端口没有替换，是否存在此端口未开通 https 的情况代码做了什么清楚多了
dev，test 都是小写，是否大写就不能匹配， 要是有枚举的可以统一处理
dbMode 没做判空，如果 dbMode 为空，则会认为是生产环境
httpGetRequest.getUri().xxx()可能报空指针异常
uri.startsWith("http://") 需要考虑前面有空格的情况
大写的 HTTP://是否也需要可也要匹配处理？现实中会出现这么多异常么，代码执行环境，输入最终是什么样的？
httpGetRequest.getUri()调用了三次，存储到变量中可以少调用两次
代码中多处字面量（dev, test, http, https)，需要常量化，dbmode 适合枚举化


编码规范
日志规范
超时问题
多线程逻辑，使用线程池创建线程
接口保护检查


1.  重试和幂等
    - 系统间的数据同步，如果失败，是否有重试机制
    - 失败重试调用，接口是否支持幂等
    - 文件导入任务，如果中断，是否有重启任务的机制

