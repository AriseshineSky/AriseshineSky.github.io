---
layout: post
title: Table-Driven Approach - a more elegant form of if-else or switch-case
categories: [design-pattern]
description: Table-Driven Approach
keywords: design pattern, Table-Driven Approach
mermaid: false
sequence: false
flow: false
mathjax: false
mindmap: false
mindmap2: false
---

# Table-Driven Approach
1. Direct Table Access 
Calculate the number of days in each month.
```
if(month == 1) {
    days = 31;
} else if (month = 2){
    days = 28;
} else if (month = 3){
    days = 31;
} else if (month = 4){
    days = 30;
} else if (month = 5){
    days = 31;
} else if (month = 6){
    days = 30;
} else if (month = 7){
    days = 31;
} else if (month = 8){
    days = 31;
} else if (month = 9){
    days = 30;
} else if (month = 10){
    days = 31;
} else if (month = 11){
    days = 30;
} else if (month = 12){
    days = 31;
}
```
Save this data into a table and create this table:

```
[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
```

```
charType = charTypeTable[inputChar];
```
