---
title: "洋葱架构、事件驱动与 GitLab 架构模式对照"
date: 2026-05-31 17:30:00 +0800
categories: [GitLab, Architecture]
tags: [onion-architecture, event-driven, cqrs, modular-monolith, layered-architecture]
description: >-
  讲解洋葱架构、事件驱动、CQRS、分层架构等概念，并与 GitLab 模块化单体中的 pragmatic 实现对照。
---

> 本文补充 [整洁架构](/posts/gitlab-clean-architecture/)、[六边形架构](/posts/gitlab-hexagonal-architecture/)、[DDD 战略模式](/posts/gitlab-ddd-strategic-patterns/)，覆盖其他常见架构术语。

## 1. 架构模式关系图

```
                    ┌─────────────────┐
                    │   DDD           │  战略：Bounded Context、Event
                    │  (战略+战术)     │  战术：Entity、Aggregate、Service
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
┌───────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ Layered       │  │ Clean / Onion   │  │ Hexagonal       │
│ (经典三层)     │  │ (同心圆+依赖向内) │  │ (Ports/Adapters)│
└───────────────┘  └─────────────────┘  └─────────────────┘
        │                    │                    │
        └────────────────────┼────────────────────┘
                             ▼
                    ┌─────────────────┐
                    │ Event-Driven    │  GitLab: EventStore
                    │ CQRS (读写分离)  │  GitLab: Finder vs Service
                    │ Modular Monolith│  GitLab: bounded_contexts.yml
                    └─────────────────┘
```

---

## 2. 洋葱架构（Onion Architecture）

Jeffrey Palermo 提出，与 Clean Architecture **几乎同构**：Domain 在最中心，Infrastructure 在最外。

### 2.1 层次（内 → 外）

| 层 | 内容 | GitLab |
|----|------|--------|
| **Domain Model** | Entity、Value Object、Domain Service | `app/models/`、PORO |
| **Domain Services** | 跨 Entity 的领域逻辑 | Entity 方法、少量 `lib/gitlab/` |
| **Application Services** | Use Case 编排 | `app/services/<context>/` |
| **Infrastructure** | DB、MQ、外部 API | ActiveRecord、Gitaly、Sidekiq |

### 2.2 与 Clean Architecture 的唯一强调点

洋葱架构更明确区分 **Domain Service** vs **Application Service**：

| 类型 | 职责 | GitLab 实例 |
|------|------|-------------|
| **Domain Service** | 无状态领域逻辑，不属于单个 Entity | `Gitlab::UserAccess`（权限计算）、`Releases::TriggeredHooks` |
| **Application Service** | 编排、事务、副作用 | `Releases::CreateService` |

```ruby
# Domain Service 风格 — 封装跨 Entity 逻辑
# app/models/projects/triggered_hooks.rb
module Projects
  class TriggeredHooks
    def execute
      @relations.each { |hooks| hooks.hooks_for(@scope)... }
    end
  end
end
```

```ruby
# Application Service — 编排完整用例
# app/services/releases/create_service.rb
def execute
  return error unless allowed?
  tag = ensure_tag
  create_release(tag, evidence_pipeline)
end
```

GitLab **不严格区分** 目录；两者都在 `app/models/` 或 `app/services/`，靠命名和职责区分。

---

## 3. 经典分层架构（Layered Architecture）

```
Presentation  →  Controller / API / GraphQL
Business      →  Service
Persistence   →  ActiveRecord / Finder
Database      →  PostgreSQL
```

### GitLab 的映射与偏离

| 经典层 | GitLab | 偏离 |
|--------|--------|------|
| Presentation | `app/controllers/`、`lib/api/` | 不受 BC 约束 |
| Business | `app/services/` | 称 Use Case 更准确 |
| Persistence | `app/models/`（AR 混合了 Domain+Persistence） | **Active Record 模式**：Entity 即 ORM |
| Database | `db/` | 分片、Cells |

**Active Record 模式**（Fowler）：Entity 类同时负责持久化，Domain 与 Infrastructure **未分离**——GitLab 的主要 pragmatic 妥协。

---

## 4. 事件驱动架构（Event-Driven Architecture）

### 4.1 概念

组件通过 **事件** 异步通信，降低时间耦合。

### 4.2 GitLab EventStore

官方动机（`doc/development/event_store.md`）：消除 `PostReceive` 等 God Worker 的跨域耦合。

**Without EventStore（紧耦合）**：

```
Ci::CreatePipelineService ──perform_async──▶ MergeRequests::UpdateHeadPipelineWorker
                         ──perform_async──▶ Namespaces::Onboarding::Worker
```

**With EventStore（事件驱动）**：

```
Ci::CreatePipelineService ──publish──▶ Ci::PipelineCreatedEvent
                                           │
              ┌────────────────────────────┼────────────────────────────┐
              ▼                            ▼                            ▼
   MergeRequests::UpdateHeadPipelineWorker   Onboarding Worker   ...
```

### 4.3 事件类型

| 类型 | GitLab |
|------|--------|
| **Domain Event** | `Projects::ProjectCreatedEvent`、`Ci::PipelineCreatedEvent` |
| **Integration Event** | 同上，通过 Sidekiq 跨 BC 传递 |
| **Event Notification** | Webhook（`HookData::ReleaseBuilder`）— 对外部系统 |

### 4.4 实例：Pipeline 创建

```ruby
# 发布方 — app/services/ci/create_pipeline_service.rb
Gitlab::EventStore.publish(
  Ci::PipelineCreatedEvent.new(data: {
    pipeline_id: pipeline.id,
    partition_id: pipeline.partition_id
  })
)
```

```ruby
# 订阅方 — lib/gitlab/event_store/subscriptions/merge_requests_subscriptions.rb
store.subscribe ::MergeRequests::UpdateHeadPipelineWorker, to: ::Ci::PipelineCreatedEvent
```

发布方 **不知道** 有哪些订阅者——开闭原则。

---

## 5. CQRS（Command Query Responsibility Segregation）

### 5.1 概念

**写（Command）** 与 **读（Query）** 分离：不同模型、不同路径。

### 5.2 GitLab 的轻量 CQRS

GitLab **没有** 独立的 Read Model 数据库，但有清晰的 **读写分离**：

| | Command（写） | Query（读） |
|---|--------------|-------------|
| **入口** | REST POST/PUT/DELETE、GraphQL Mutation | REST GET、GraphQL Query |
| **编排** | `app/services/*/` Use Case | `app/finders/` Finder |
| **返回** | `ServiceResponse`、side effects | `ActiveRecord::Relation`、预加载 |
| **副作用** | Webhook、Worker、Audit | 无 |

```ruby
# Command
Releases::CreateService.new(project, user, params).execute

# Query
ReleasesFinder.new(project, user, params).execute
```

### 5.3 读模型 Adapter

查询结果经 **Serializer / Entity** 转为 API 响应（Presentation 层读模型）：

```ruby
present releases, with: Entities::Release
```

**不是** 经典 CQRS 的独立投影表，而是 **同库读写 + 职责分离**。

### 5.4 何时 GitLab 接近完整 CQRS

- **Value Stream Analytics** 等分析后端使用聚合表，不直接查 Issue/MR 核心表（`doc/development/value_stream_analytics/`）
- **ClickHouse** 分析（EE）— 独立读存储

---

## 6. 模块化单体（Modular Monolith）

### 6.1 概念

单一部署单元，内部按模块/上下文划分，兼顾单体运维与模块化开发。

### 6.2 GitLab 实现

| 机制 | 路径 |
|------|------|
| Bounded Context 注册 | `config/bounded_contexts.yml` |
| 命名空间隔离 | `Ci::`、`Releases::`、`MergeRequests::` |
| 跨模块通信 | EventStore、少量 Service 调用 |
| 未来 Cells | 按 Organization 分片 |

与微服务对比：

| | Modular Monolith | Microservices |
|---|------------------|---------------|
| 部署 | 一个 GitLab 实例 | 多服务 |
| 边界 | Ruby namespace | 网络 + 独立 DB |
| GitLab 选择 | ✓ 当前方向 | 部分提取（Gitaly、Workhorse） |

**已拆分的基础设施服务**：Gitaly（Git）、Workhorse（HTTP 代理）— 作为 Secondary Adapter 独立进程。

---

## 7. 内外层依赖关系（概要）

洋葱 / 整洁 / 六边形共享 **依赖向内** 规则。GitLab 通过 **调用方向** 体现，而非独立 `domain/` 目录。

```
外层 Adapter（api/controllers/workers）
        │ 只向内调用
        ▼
Application Service（app/services/）
        │
        ▼
Domain Model（app/models/）
        │ 经 Gateway/Builder 访问
        ▼
Infrastructure（Gitaly、Sidekiq、PostgreSQL）
```

详细分析见：

- [整洁架构 §7–§8](/posts/gitlab-clean-architecture/) — 依赖链 + 设计模式分层
- [六边形架构 §6–§7](/posts/gitlab-hexagonal-architecture/) — Primary/Secondary 边界 + Port

---

## 8. 设计模式在 GitLab 中的体现

GitLab 未系统标注 GoF 模式名，但源码中广泛存在。下表按 **用途** 归类，并给出可跳转的源码路径。

### 8.1 创建型模式

| 模式 | 作用 | GitLab 实例 | 路径 |
|------|------|-------------|------|
| **Factory Method** | 按上下文创建不同实现 | `ExportStatus.for_context` 选 Online/Offline | `app/models/import/export_status.rb` |
| **Factory Method** | 导入时 find-or-create | `ImportExport::Project::ObjectBuilder` | `lib/gitlab/import_export/project/object_builder.rb` |
| **Builder** | 分步构建复杂 DTO | `HookData::ReleaseBuilder#build` | `lib/gitlab/hook_data/release_builder.rb` |
| **Singleton**（框架级） | Rails 单例组件 | `Gitlab::Redis`、`Gitlab::CurrentSettings` | `lib/gitlab/` |

```ruby
# Factory Method — 调用方只依赖抽象
Import::ExportStatus.for_context(tracker, relation)

# Builder — Entity → Webhook Hash
Gitlab::HookData::ReleaseBuilder.new(release).build('create')
```

### 8.2 结构型模式

| 模式 | 作用 | GitLab 实例 | 路径 |
|------|------|-------------|------|
| **Adapter** | 协议/技术适配 | REST API → Service；Gitaly → `Git::Repository` | `lib/api/`、`lib/gitlab/git/repository.rb` |
| **Facade** | 简化复杂子系统 | `Gitlab::Git::Repository` 隐藏 gRPC | `lib/gitlab/git/repository.rb` |
| **Facade** | 聚合根统一入口 | `Project` delegate → `ProjectSetting` | `app/models/project.rb` |
| **Decorator/Presenter** | 扩展展示而不改 Entity | `LinkPresenter#direct_asset_url` | `app/presenters/releases/link_presenter.rb` |
| **Composite** | 树形结构统一处理 | Work Item Widget 体系 | `app/models/work_items/widgets/` |

```ruby
# Adapter — Gitaly 适配
module Gitlab::Git
  class Repository
    def commit(sha); end  # 内部 gRPC，外部领域 API
  end
end

# Presenter — 展示层 Decorator
def direct_asset_url
  return @subject.url unless @subject.filepath
  release.download_url(@subject.filepath)
end
```

### 8.3 行为型模式

| 模式 | 作用 | GitLab 实例 | 路径 |
|------|------|-------------|------|
| **Command** | 封装请求为对象 | `CreateService#execute` | `app/services/releases/create_service.rb` |
| **Template Method** | 基类定义骨架，子类填充 | `BaseService` 共享 milestone/tag 逻辑 | `app/services/releases/base_service.rb` |
| **Strategy** | 算法可替换 | `Import::Offline::ExportStatus` vs `BulkImports::ExportStatus` | `app/models/import/` |
| **Observer** | 状态变化通知 | EventStore 订阅 Worker | `lib/gitlab/event_store/subscriptions/` |
| **Mediator** | 多对象通过中介通信 | `Gitlab::EventStore` 解耦发布/订阅 | `lib/gitlab/event_store/store.rb` |
| **State** | 对象随状态改变行为 | `MergeRequests::MergeData` state machine | `app/models/merge_requests/merge_data.rb` |
| **Chain of Responsibility** | 请求沿链传递 | Policy 规则链 `DeclarativePolicy` | `app/policies/` |

```ruby
# Command
module Releases
  class CreateService
    def execute; end  # 统一入口
  end
end

# Observer + Mediator
Gitlab::EventStore.publish(Ci::PipelineCreatedEvent.new(...))
store.subscribe MergeRequests::UpdateHeadPipelineWorker, to: Ci::PipelineCreatedEvent

# Template Method — 子类未实现则抛错
def in_progress?
  raise Gitlab::AbstractMethodError
end
```

### 8.4 架构 / 领域模式（非 GoF）

| 模式 | 作用 | GitLab 实例 |
|------|------|-------------|
| **Repository（变体）** | 持久化抽象 | ActiveRecord + `Release.find`（无独立 Repository 类） |
| **Query Object** | 复杂只读查询 | `ReleasesFinder#execute` |
| **Unit of Work** | 事务边界 | `ApplicationRecord.transaction` in `UpdateService` |
| **Anti-Corruption Layer** | 外部模型翻译 | `GithubImport::Representation::Issue.from_api_response` |
| **Domain Event** | 跨 BC 异步事实 | `Projects::ProjectCreatedEvent` |
| **Service Layer** | 用例编排 | `app/services/<context>/` |
| **Data Transfer Object** | 跨层数据传输 | `lib/api/entities/release.rb`（非 Domain Entity） |

### 8.5 设计模式与架构层对应

| 架构层 | 常见模式 |
|--------|----------|
| Entity | State、Strategy（enum） |
| Application Service | Command、Template Method |
| Finder | Query Object |
| Primary Adapter | Adapter |
| Secondary Adapter | Adapter、Builder、Facade |
| 跨 BC | Observer、Mediator、Domain Event |
| Import 边界 | ACL、Factory、Strategy |

### 8.6 SOLID 与设计模式的关系

| 原则 | 模式支撑 | GitLab 实例 |
|------|----------|-------------|
| **S** 单一职责 | Command 拆分用例 | `Links::CreateService` 独立于 `CreateService` |
| **O** 开闭 | Observer/Event | 新 Worker 订阅 Event，不改 `CreatePipelineService` |
| **L** 里氏替换 | Strategy | `Offline::ExportStatus` 可替换 `ExportStatus` |
| **I** 接口隔离 | Event Schema | 只暴露 `pipeline_id` 等必要字段 |
| **D** 依赖倒置 | Port/Event | Service publish Event，不依赖具体 Worker |

---

## 9. 其他相关概念

### 9.1 Anti-Corruption Layer（防腐层）

见 [DDD 战略模式](/posts/gitlab-ddd-strategic-patterns/)：`Gitlab::GithubImport::Representation::*`。

### 9.2 Gateway / Facade

| 模式 | GitLab |
|------|--------|
| **Gateway** | `Gitlab::Git::Repository` 封装 Gitaly |
| **Facade** | `Project` delegate 到 `ProjectSetting` |

### 9.3 Repository 模式

GitLab **基本不用** classic Repository 接口：

```ruby
Release.find(id)
ReleasesFinder.new(...).execute
```

ActiveRecord + Finder 是 pragmatic 替代。

---

## 10. 架构模式对照总表

| 模式 | 核心思想 | GitLab 实现程度 | 典型路径 |
|------|----------|-----------------|----------|
| **Layered** | 分层 | 部分（AR 混合层） | controllers → services → models |
| **Clean** | 依赖向内 | 部分 | services 不依赖 api |
| **Onion** | Domain 中心 | 部分 | models + services |
| **Hexagonal** | Ports/Adapters | 较好 | api/controllers ↔ services ↔ git/gitaly |
| **DDD 战略** | Bounded Context | 推进中 | bounded_contexts.yml |
| **DDD 战术** | Entity/Aggregate | 部分 | models、Event |
| **Event-Driven** | 事件解耦 | 较好（新代码） | EventStore |
| **CQRS** | 读写分离 | 轻量 | Service vs Finder |
| **Modular Monolith** | 模块单体 | 官方方向 | namespace + Event |

---

## 11. 如何选择阅读路径

| 你想理解… | 读哪篇 |
|-----------|--------|
| Release 完整分层 | [Release 文档](/posts/gitlab-release/) |
| Project 的 DDD 战术 | [Project DDD](/posts/gitlab-ddd-domain-objects/) |
| 限界上下文与 Event | [DDD 战略](/posts/gitlab-ddd-strategic-patterns/) |
| 依赖规则 + 模式分层 | [整洁架构 §7–§8](/posts/gitlab-clean-architecture/) |
| Port/Adapter + 模式 | [六边形架构 §6–§7](/posts/gitlab-hexagonal-architecture/) |
| GoF 模式总表 + CQRS | 本文 §8 |

---

## 12. 关键路径速查

| 概念 | 路径 |
|------|------|
| EventStore | `lib/gitlab/event_store/`、`doc/development/event_store.md` |
| 订阅注册 | `lib/gitlab/event_store/subscriptions/` |
| Command | `app/services/` |
| Query | `app/finders/` |
| Modular Monolith | Handbook + `config/bounded_contexts.yml` |
| Import ACL | `lib/gitlab/github_import/representation/` |
| Git Gateway | `lib/gitlab/git/repository.rb` |
| 软件设计指南 | `doc/development/software_design.md` |

---

## 13. 一句话总结

GitLab 不是某一种架构的教科书实现，而是 **Layered + DDD Modular Monolith + Hexagonal Adapters + Event-Driven 解耦 + 轻量 CQRS** 的组合；新代码趋向 Use Case、Finder、EventStore，legacy 仍保留 Active Record 与上帝对象，正在逐步治理。
