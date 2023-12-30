---
layout: post
title: Python multithreading tips: A better alternative to ```time.sleep``` for pausing!
categories: [python]
description: The method of waiting in Python multithreading environment
keywords: python, multithreading, sleep, event
mermaid: false
sequence: false
flow: false
mathjax: false
mindmap: false
mindmap2: false
---

# Threading Event
```python
import threading

event = threading.Event()
event.wait(5)

class Checker(threading.Thread):
    def __init__(self, event):
        super().__init__()
        self.event = event

    def run(self):
        while not self.event.is_set():
            print("check data in redis")
            time.sleep(60)

trigger_async_task()
event = threading.Event()
checker = Checker(event)
checker.start()
if user_cancel_task():
    event.set()


```

```python
import threading
import time

def worker(event):
    print("Worker thread is waiting.")
    event.wait()
    print("Worker thread is awake and continuing.")

def main():
    event = threading.Event()

    thread = threading.Thread(target=worker, args=(event,))
    thread.start()

    time.sleep(3)
    print("Main thread is notifying the worker.")
    event.set()

    thread.join()
```
