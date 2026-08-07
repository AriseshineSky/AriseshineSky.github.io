---
title: "Autoloading and Reloading Constants"
---

# 1. Introduction

In an ordinary Ruby program, you explicitly load the files that define classes and modules you want to use. You normally issue `require` calls. This is not the case in Rails applications, where application classes and modules are just available everywhere without `require` calls. This is possible thanks to a couple of Zeitwerk loaders Rails sets up on your behalf, which provide **autoloading**, **reloading**, and **eager loading**.

That convenience is easy to over-read. The next sentence from the Rails Guides is the real boundary:

> **On the other hand, those loads do not manage anything else.** In particular, they do not manage the Ruby standard library, gem dependencies, Rails components, or even (by default) the application `lib` directory. **That code has to be loaded as usual.**

Read it as a hard scope cut, not a footnote:

| Zeitwerk *does* manage | Zeitwerk *does not* manage |
|------------------------|----------------------------|
| App code under `app/` (models, controllers, jobs, …) | Ruby standard library (`Set`, `JSON`, …) |
| Autoload / reload / eager load for those paths | Gem dependencies (`nokogiri`, `sidekiq`, …) |
| Constant ↔ file mapping Rails configured for you | Rails framework components themselves |
| | Application `lib/` **by default** |

So: `User`, `OrdersController`, `ChargeJob` can appear without `require`. But `require "set"`, Bundler-loaded gems, Rails internals, and (unless you opt in) anything under `lib/` still follow ordinary Ruby loading. Autoloading is **not** a global replacement for `require`—it is a managed island for application constants.
