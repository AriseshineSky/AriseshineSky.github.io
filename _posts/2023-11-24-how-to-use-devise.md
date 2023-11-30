---
layout: post
title: 如何使用devise
categories: [ruby]
description: 在Rails中使用devise实现用户的注册，登陆
keywords: rails, devise
mermaid: false
sequence: false
flow: false
mathjax: false
mindmap: false
mindmap2: false
---

# How to use Devise in Rails

1. 在Gemfile中添加```gem devise```最新版本参考文档 [devise](https://rubygems.org/gems/devise)
2. 运行```bundle install```
3. 安装 devise 相关组件 ```rails generate devise:install```
4. 执行命令```rails g devise:views```，生成 devise 的视图文件
5. 生成需要用到 devise 的模型，这里使用 user 作为模型的名字，```rails g devise user```，运行了这条命令之后，不仅创建里模型，生成了对应的 migration, 而且路由中会自动生成一个```devise_for :users```。运行 ```rails db:migrate``` , 执行迁移文件
6. 判断用户是否登录 ```user_signed_in?``` 可以在 view 里使用，这样就可以根据是否登录来显示是登录，还是退出
    ```ruby
      <% if user_signed_in? %>
        <%= link_to('Sign Out', destroy_user_session_path, method: :delete) %>
      <% else %>
        <%= link_to('Register', new_user_registration_path(:user)) %>
        <%= link_to('Sign In', new_session_path(:user)) %>
      <% end %>
    ```
7. 为 users 表添加字段时，需要自定义 controller ，这样注册时新加的字段才能保存到数据库。
[https://gist.github.com/withoutwax/46a05861aa4750384df971b641170407](https://gist.github.com/withoutwax/46a05861aa4750384df971b641170407)
[https://dev.to/casseylottman/adding-a-field-to-your-sign-up-form-with-devise-10i1](https://dev.to/casseylottman/adding-a-field-to-your-sign-up-form-with-devise-10i1)
