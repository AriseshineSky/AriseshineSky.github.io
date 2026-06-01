---
title: "GitLab 中的 DDD 战略模式与跨上下文设计"
date: 2026-05-31 16:00:00 +0800
categories: [GitLab, DDD]
tags: [bounded-context, domain-event, event-store, anti-corruption-layer, ubiquitous-language, context-mapping]
description: >-
  用 GitLab 源码实例讲解 DDD 战略模式：限界上下文、上下文映射、通用语言、领域事件、EventStore、防腐层与模块化单体。
---

> 本文基于 GitLab 源码与 `doc/development/software_design.md`、`doc/development/event_store.md` 整理。  
> 战术模式（Entity、Aggregate 等）见 [Project 示例](/posts/gitlab-ddd-domain-objects/) 与 [Release 示例](/posts/gitlab-release/)。

## 1. DDD 战略 vs 战术

| 层次 | 关注点 | GitLab 中的落点 |
|------|--------|-----------------|
| **战略设计** | 系统如何拆分为上下文、如何协作 | `config/bounded_contexts.yml`、EventStore、Import ACL |
| **战术设计** | 单个上下文内部如何建模 | `app/models/`、`app/services/`、Finder |

本文聚焦 **战略模式** 及跨上下文协作。

---

## 2. 限界上下文（Bounded Context）

### 2.1 概念

限界上下文 = 有明确边界、统一语言、独立演进的业务域。在 GitLab 中用 **Ruby 命名空间** 表达。

注册表：`config/bounded_contexts.yml`（RuboCop `Gitlab/BoundedContexts` 强制新类必须落在其中）。

```yaml
Releases:
  feature_categories:
    - release_orchestration
    - release_evidence

Projects:
  description: Managing projects as workspaces and their lifecycle.
             Feature specific behavior must not go here.
```

### 2.2 设计原则（官方文档）

- **Project / Group 是 tenant 容器**，不是把所有 feature 都塞进 `Projects::`
- Repository 逻辑在 `Repositories::`，CI 在 `Ci::`，Release 在 `Releases::`
- 命名空间应 **深**（nested），如 `Ci::Config::`、`MergeRequests::`

### 2.3 实例：Release 与 Project 的边界

```
Projects::ReleasePublishedEvent   ← Event 放在 Project 上下文
Releases::CreateService           ← 发布业务在 Release 上下文
```

Release 创建完成后，由 `Projects::` 命名空间的事件通知其他域——体现 **上下文各自负责自己的概念**。

---

## 3. 通用语言（Ubiquitous Language）

GitLab 强制产品术语进入代码命名，禁止 CRUD 术语泄漏。

```ruby
# Good — 产品语言
Projects::CreateService
Epic::AddExistingIssueService
Releases::CreateService

# Bad — 框架/CRUD 术语
EpicIssues::CreateService
ReleaseLinks::CreateService
```

`doc/development/software_design.md` 说明：类名、Service 名、Event 名都应对齐产品文档中的用词。

**Event 命名规范**（`doc/development/event_store.md`）：

```
<DomainObject><PastTenseAction>Event

Projects::ProjectCreatedEvent       ✓
Projects::AddProjectEvent           ✗
```

---

## 4. 上下文映射（Context Mapping）

GitLab 没有画 Context Map 文档，但代码里存在典型映射关系：

| 映射模式 | 含义 | GitLab 实例 |
|----------|------|-------------|
| **Shared Kernel** | 共享核心模型 | `User`、`Project` 被多上下文引用（tenant） |
| **Customer-Supplier** | 一方依赖另一方 API | `Releases::CreateService` → `Tags::CreateService` |
| **Conformist** | 下游完全接受上游模型 | Import 最终写入 GitLab AR 模型 |
| **Anti-Corruption Layer** | 翻译外部模型 | `Gitlab::GithubImport::Representation::*` |
| **Published Language** | 公开的事件契约 | `Gitlab::EventStore::Event` + JSON Schema |
| **Open Host Service** | 对外 REST/GraphQL | `lib/api/`、`app/graphql/` |

### 4.1 Customer-Supplier 示例

```ruby
# app/services/releases/create_service.rb
result = Tags::CreateService
  .new(project, current_user)
  .execute(tag_name, ref, tag_message)
```

`Releases::`（Customer）调用 `Tags::`（Supplier）创建 tag，不直接操作 Gitaly。

### 4.2 Anti-Corruption Layer 示例

GitHub Import 将外部 API 响应翻译为 GitLab 内部 DTO：

```ruby
# lib/gitlab/github_import/representation/issue.rb
module Gitlab
  module GithubImport
    module Representation
      class Issue
        def self.from_api_response(issue, additional_data = {})
          hash = {
            iid: issue[:number],
            title: issue[:title],
            state: issue[:state] == 'open' ? :opened : :closed,
            # ...
          }
        end
      end
    end
  end
end
```

外部 GitHub 的 `:number`、`:body` 不会直接污染 GitLab 的 `Issue` 模型；先经 **Representation** 层转换。

Import 还有 `Gitlab::ImportExport::Project::ObjectBuilder` 负责 find-or-create 关联对象，隔离导入场景与正常 CRUD。

---

## 5. 领域事件（Domain Event）

### 5.1 概念

「领域中已发生的重要事实」，用于跨上下文 **异步解耦**。

基类（`lib/gitlab/event_store/event.rb`）：

```ruby
# 定义在 app/events/<namespace>/
class Projects::ProjectCreatedEvent < Gitlab::EventStore::Event
  def schema
    {
      'type' => 'object',
      'properties' => {
        'project_id' => { 'type' => 'integer' },
        'namespace_id' => { 'type' => 'integer' },
        'root_namespace_id' => { 'type' => 'integer' }
      },
      'required' => %w[project_id namespace_id root_namespace_id]
    }
  end
end
```

发布：

```ruby
Gitlab::EventStore.publish(
  Projects::ProjectCreatedEvent.new(data: { project_id: project.id, ... })
)
```

### 5.2 为什么需要 EventStore

官方文档指出 `PostReceive` worker 等 **上帝 Worker** 违反 SRP、破坏域边界。EventStore 将：

```
Ci::CreatePipelineService  ──publish──▶  Ci::PipelineCreatedEvent
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    ▼                         ▼                         ▼
     MergeRequests::UpdateHeadPipelineWorker   ...其他订阅 Worker
```

替代直接在 `CreatePipelineService` 里 `perform_async` 其他域的 Worker。

### 5.3 订阅注册

```ruby
# lib/gitlab/event_store/subscriptions/merge_requests_subscriptions.rb
store.subscribe ::MergeRequests::UpdateHeadPipelineWorker, to: ::Ci::PipelineCreatedEvent
store.subscribe ::MergeRequests::CreateApprovalEventWorker, to: ::MergeRequests::ApprovedEvent
```

订阅按上下文分文件注册（`lib/gitlab/event_store/subscriptions/`），清晰展示 **谁关心什么事件**。

### 5.4 发布方示例

```ruby
# app/services/ci/create_pipeline_service.rb
Gitlab::EventStore.publish(
  Ci::PipelineCreatedEvent.new(data: {
    pipeline_id: pipeline.id,
    partition_id: pipeline.partition_id
  })
)
```

Pipeline 创建的主事务 **不再直接调用** MR 域的 Worker，符合 **开闭原则**。

---

## 6. 策略模式 + 工厂（Import ExportStatus）

跨上下文的 **同一概念、不同实现**：

```ruby
# app/models/import/export_status.rb
def self.for_context(pipeline_tracker, relation)
  if pipeline_tracker.entity.bulk_import.offline_export?
    Import::Offline::ExportStatus.new(pipeline_tracker, relation)
  else
    ::BulkImports::ExportStatus.new(pipeline_tracker, relation)
  end
end
```

抽象基类定义接口（`in_progress?`、`failed?`…），子类实现不同导入场景——DDD 中的 **Policy/Strategy** 与 **Factory Method** 组合。

---

## 7. 模块化单体（Modular Monolith）

GitLab 官方方向（Handbook: Modular Monolith）：

- **一个 deployable**（单体），但内部按 Bounded Context 划分
- 用 **命名空间 + EventStore** 降低耦合，而非微服务拆分
- 长期目标：Cells 架构下按 Organization 分片

当前 pragmatic 状态：

| 理想 | 现实 |
|------|------|
| 严格上下文隔离 | `Project` 仍关联大量子系统（上帝对象） |
| 所有类在 BC 内 | 部分 legacy 顶层类仍在迁移中 |
| Event 驱动一切 | 新旧代码并存，部分仍直接调 Worker |

---

## 8. 与 Textbook DDD 的差异

| Textbook | GitLab |
|----------|--------|
| 显式 Context Map 文档 | `bounded_contexts.yml` + 代码结构 |
| Domain 层独立目录 | 分散在 `app/models`、`app/services`、`lib/gitlab` |
| Aggregate Repository | ActiveRecord + Finder |
| 统一 Event Bus 框架 | 自研 `Gitlab::EventStore`（Sidekiq 之上） |

---

## 9. 关键路径速查

| 概念 | 路径 |
|------|------|
| Bounded Context 注册 | `config/bounded_contexts.yml` |
| 设计指南 | `doc/development/software_design.md` |
| EventStore 指南 | `doc/development/event_store.md` |
| Event 基类 | `lib/gitlab/event_store/event.rb` |
| Event 定义 | `app/events/` |
| 订阅注册 | `lib/gitlab/event_store/subscriptions/` |
| Import ACL | `lib/gitlab/github_import/representation/` |
| Import Factory | `lib/gitlab/import_export/project/object_builder.rb` |

---

## 10. 阅读建议

1. 读 `config/bounded_contexts.yml` 建立上下文全景。
2. 跟踪 `Ci::CreatePipelineService` → `PipelineCreatedEvent` → `MergeRequests::UpdateHeadPipelineWorker`。
3. 对比 Import 的 `Representation::Issue.from_api_response` 与正常 `Issues::CreateService`。
4. 结合 [Release 文档](/posts/gitlab-release/) 看跨上下文协作。
