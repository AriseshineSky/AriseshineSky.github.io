---
layout: post
title: 部署 Rails 应用
categories: [rails]
description: 在 utuntu 上部署 rails 应用
keywords: rails, puma, nginx
mermaid: false
sequence: false
flow: false
mathjax: false
mindmap: false
mindmap2: false
---

# 在 ubuntu 上

awk 的数组是关联数组，索引下标可为数值，包括负数，小数等，也可为字符串
在内部，awk 数组的索引全都是字符串，即使是数值索引在使用时内部也会转换成字符串
awk 的数组元素的顺序和元素插入时的顺序很可能是不同的
awk 支持数组的数组

### awk 访问 赋值
```
arr[idx]
arr[idx] = value

awk '
    begin {
        arr[1] = 11
        arr["1"] = 111
        arr["a"] = "aa"
    }
'
```

### 通过索引的方式访问数组中不存在的元素时， 会返回空字符串，同时会创建这个元素并将其值设置为空字符串

```
awk '
    BEGIN {
        arr[-1] = 3;
        print length(arr);
        print arr[1];
        print length(arr);
    }
'
```

###  awk 删除数组元素，删除不存在的元素不会报错
```delete arr``` :删除数组所有元素

```
awk '
    BEGIN {
        arr[1]=1;
        arr[2]=2;
        arr[3]=3;
        delete arr[2];
        print length(arr)
    }
'
```

###  常用方法  
    1. 文件按行去重 awk "!seen[$0]++" file_name > uniqu_line_file_name
