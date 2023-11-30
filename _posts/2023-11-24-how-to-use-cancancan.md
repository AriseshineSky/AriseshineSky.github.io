---
layout: post
title: UJS in Rails 7
categories: [string]
description: Add Rails UJS in rails 7
keywords: rails 7, rails ujs
mermaid: false
sequence: false
flow: false
mathjax: false
mindmap: false
mindmap2: false
---
# How to use UJS in rails 7

To add rails-ujs to Rails 7 you should to do following steps:

1. Pin it, to let the application know, which package to use. Enter in bash:
```./bin/importmap pin @rails/ujs```
2. And now you have in your ```config/importmap.rb``` file something like this:
```pin "@rails/ujs", to: "https://ga.jspm.io/npm:@rails/ujs@7.0.1/lib/assets/compiled/rails-ujs.js"```
3. Now include ```@rails/ujs``` to your javascript. In file ```javascript/controllers/application.js``` add:
```javascript
import Rails from '@rails/ujs';
Rails.start();
```
4. Restart your application server
