---
icon: fas fa-book
order: 2
---

# GitLab 学习笔记

阅读 [gitlab-org/gitlab](https://gitlab.com/gitlab-org/gitlab) 源码时的分析笔记，与官方文档和代码目录结构对照整理。

## 目录

### DDD 与领域模型

- [GitLab 中的 DDD 概念与 Project 示例](/posts/gitlab-ddd-domain-objects/) — Bounded Context、Entity、Aggregate、Domain Event 等，以 `Project` / `ProjectSetting` 为例
- [GitLab 中的 DDD 战略模式与跨上下文设计](/posts/gitlab-ddd-strategic-patterns/) — 限界上下文、上下文映射、EventStore、防腐层、模块化单体

### Project

- [GitLab Project 创建：代码分层与架构原则](/posts/gitlab-project-create-layering/) — 以创建 Project 为完整用例，分析 Namespace + Gitaly 建库、Import ACL、EventStore 与 Issue 的模式差异

### Issue / WorkItems

- [GitLab Issue 创建：代码分层与架构原则](/posts/gitlab-issue-create-layering/) — 以创建 Issue 为完整用例，分析 Adapter → Service → Model → Worker → EventStore 分层与 DDD/Clean 原则

### Release

- [GitLab Release：概念、代码实现与 DDD 分析](/posts/gitlab-release/) — Release 产品含义、**Source PORO**、Model/Service/Client 分工、Use Case / Finder / 适配器分层
- [GitLab Release 创建：代码分层与架构原则](/posts/gitlab-release-create-layering/) — 以创建 Release 为完整用例，Tag + Evidence + Catalog 编排与 Issue/Project 对照

### 架构模式

- [整洁架构（Clean Architecture）在 GitLab 中的映射](/posts/gitlab-clean-architecture/) — 同心圆分层、**§3.4 Client/Service**、**§7 内外层依赖**、**§8 设计模式**
- [六边形架构（Hexagonal Architecture）在 GitLab 中的实践](/posts/gitlab-hexagonal-architecture/) — Primary/Secondary Adapter、**§6 依赖方向**、**§7 设计模式**
- [洋葱架构、事件驱动与 GitLab 架构模式对照](/posts/gitlab-onion-and-event-driven/) — CQRS、Event-Driven、**§8 GoF 模式总表**、SOLID

---

## 推荐阅读顺序

1. [Release 创建](/posts/gitlab-release-create-layering/)、[Issue 创建](/posts/gitlab-issue-create-layering/) 或 [Project 创建](/posts/gitlab-project-create-layering/) — 从完整写用例入手；[Release 全景](/posts/gitlab-release/) 作参考
2. [DDD 战略模式](/posts/gitlab-ddd-strategic-patterns/) — 理解跨上下文协作
3. [整洁架构](/posts/gitlab-clean-architecture/) 或 [六边形架构](/posts/gitlab-hexagonal-architecture/) — 理解分层与适配器
4. [架构模式对照](/posts/gitlab-onion-and-event-driven/) — 总览所有术语
5. [Project DDD](/posts/gitlab-ddd-domain-objects/) — 深入战术模式与上帝对象治理

---

## 本地源码

笔记对应的分析环境：

- GitLab 源码：`gitlab-org/gitlab`
- 笔记仓库：本站点（GitHub Pages）

有新笔记时，在此页追加链接即可。

站点托管于 [GitHub Pages](https://ariseshinesky.github.io)。
