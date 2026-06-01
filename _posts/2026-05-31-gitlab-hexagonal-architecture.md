---
title: "六边形架构（Hexagonal Architecture）在 GitLab 中的实践"
date: 2026-05-31 17:00:00 +0800
categories: [GitLab, Architecture]
tags: [hexagonal-architecture, ports-and-adapters, primary-adapter, secondary-adapter]
description: >-
  用 GitLab 源码讲解六边形架构的 Port/Adapter、驱动侧与被驱动侧适配器，以及 REST、GraphQL、Gitaly、Webhook 等实例。
---

> 六边形架构（Ports and Adapters）由 Alistair Cockburn 提出，与 Clean Architecture、洋葱架构核心思想一致：**业务逻辑在中心，外部通过适配器接入**。  
> GitLab 是 Rails 模块化单体，未显式定义 Port 接口，但结构上等价。

## 1. 六边形架构核心

```
                    ┌─────────────────────────┐
         REST API ──┤                         ├── Webhook 出站
         GraphQL  ──┤    Application Core     ├── PostgreSQL
         Web UI   ──┤  (Domain + Use Cases)   ├── Gitaly
         Sidekiq  ──┤                         ├── Redis
                    └─────────────────────────┘
                      ▲ Primary (Driving)    ▲ Secondary (Driven)
                      │ 主动调用应用          │ 应用调用外部
```

| 术语 | 含义 |
|------|------|
| **Application Core** | 领域模型 + 用例，不依赖具体技术 |
| **Port** | 应用与外部交互的 **抽象边界**（GitLab 多为隐式） |
| **Primary Adapter** | 驱动侧：UI、API、CLI 调用应用 |
| **Secondary Adapter** | 被驱动侧：DB、消息、外部服务 |

---

## 2. Application Core（应用核心）

GitLab 的核心 = **Bounded Context 内的 Model + Service**。

```ruby
# 核心：不 import Grape、ActionController
module Releases
  class CreateService < BaseService
    def execute
      # 权限、编排、持久化、副作用
    end
  end
end
```

```ruby
# 核心：领域规则
class Release < ApplicationRecord
  validate :sha_unchanged, on: :update
end
```

**核心原则**：`app/services/releases/` 和 `app/models/` 不应依赖 `lib/api/` 或 `app/controllers/`。

---

## 3. Primary Adapters（驱动侧 / 入站）

外部世界 **主动调用** GitLab 业务。

### 3.1 REST API Adapter

```ruby
# lib/api/releases.rb — Grape endpoint
post ':id/releases' do
  result = ::Releases::CreateService.new(user_project, current_user, params).execute
  present result[:release], with: Entities::Release
end
```

| 职责 | 说明 |
|------|------|
| HTTP 解析 | `declared_params` |
| 鉴权 | `authorize_create_release!` |
| 调 Core | `CreateService#execute` |
| 响应序列化 | `Entities::Release` |

### 3.2 GraphQL Adapter

```ruby
# app/graphql/mutations/releases/create.rb
def resolve(project_path:, **scalars)
  result = ::Releases::CreateService.new(project, current_user, params).execute
  { release: result[:release], errors: [] }
end
```

**同一 Port（创建 Release 用例），两个 Primary Adapter**——六边形架构的典型收益。

### 3.3 Web Controller Adapter

```ruby
# app/controllers/projects/releases_controller.rb
def index
  render json: ReleaseSerializer.new.represent(
    ReleasesFinder.new(@project, current_user, params).execute
  )
end
```

额外处理 HTML、Atom RSS、下载 redirect——Web 特有的 Adapter 逻辑。

### 3.4 Sidekiq Worker 作为 Primary Adapter

Cron / 队列 **驱动** 业务执行：

```ruby
# app/workers/releases/publish_event_worker.rb
def perform
  Release.waiting_for_publish_event.each_batch do |releases|
    Gitlab::EventStore.publish(
      Projects::ReleasePublishedEvent.new(data: { release_id: release.id })
    )
  end
end
```

Worker 是 **框架入口 Adapter**，内部调用 Core（EventStore、Service）。

### 3.5 EventStore Subscriber 作为 Primary Adapter

事件触发下游 Worker：

```ruby
# lib/gitlab/event_store/subscriptions/merge_requests_subscriptions.rb
store.subscribe ::MergeRequests::UpdateHeadPipelineWorker, to: ::Ci::PipelineCreatedEvent
```

`PipelineCreatedEvent` 是 **Port 的消息形式**；Worker 是 MR 上下文的 Adapter。

---

## 4. Secondary Adapters（被驱动侧 / 出站）

Application Core **调用** 外部系统。

### 4.1 数据库 Adapter — ActiveRecord

```ruby
# Use Case 内
release.save!
Release.where(project_id: project.id)
```

GitLab 无 Repository 接口；ActiveRecord 即 DB Adapter。Entity 继承 `ApplicationRecord` 是 Rails pragmatic 妥协。

### 4.2 Gitaly Adapter — Git 仓库

```ruby
# lib/gitlab/git/repository.rb
module Gitlab
  module Git
    class Repository
      # 封装 Gitaly gRPC，对外暴露 commit、find_tag、branch_names
      def commit(sha)
        # Gitaly RPC call
      end
    end
  end
end
```

Domain 通过 `project.repository` 访问，**不直接依赖 Gitaly protobuf**——经典 Secondary Adapter 封装。

```
Release#commit  →  project.repository  →  Gitlab::Git::Repository  →  GitalyClient  →  Gitaly
```

最底层 `Gitlab::GitalyClient::*Service` 是 **Client**（协议/重试）；`Gitlab::Git::Repository` 是面向用例的封装；`app/services/` 编排何时调用。详见 [Release §5.6 Client/Service 分工](/posts/gitlab-release/#56-client-与-service-的分工)。

### 4.3 Webhook 出站 Adapter

```ruby
# lib/gitlab/hook_data/release_builder.rb
class ReleaseBuilder < BaseBuilder
  def build(action)
    { object_kind: 'release', action: action, ... }
  end
end

# app/models/release.rb
def execute_hooks(action)
  project.execute_hooks(to_hook_data(action), :release_hooks)
end
```

Core 产生领域对象 → Builder Adapter 转为 HTTP Webhook JSON → 发送到外部系统。

### 4.4 通知 Adapter

```ruby
# create_service.rb
NotificationService.new.async.send_new_release_notifications(release)
```

`NotificationService` 封装 Email、Slack 等通道——出站 Adapter。

### 4.5 外部 Import API Adapter（入站+翻译）

GitHub API 响应 → ACL → Core：

```ruby
# lib/gitlab/github_import/representation/issue.rb
def self.from_api_response(issue, additional_data = {})
  { iid: issue[:number], title: issue[:title], ... }
end
```

Representation 层是 **Inbound Adapter + Anti-Corruption Layer** 的组合。

### 4.6 Redis / Cache Adapter

```ruby
# app/models/import/export_status.rb
Gitlab::Cache::Import::Caching.read(cache_key)
Gitlab::Cache::Import::Caching.write(cache_key, status.to_json)
```

Import 状态读写 Redis——Infrastructure Adapter。

---

## 5. Port 在 GitLab 中的体现

GitLab **很少**写 `interface CreateReleasePort`，Port 多为 **隐式**：

| Port 类型 | GitLab 体现 |
|-----------|-------------|
| **Use Case Port** | `CreateService#execute` 方法签名 |
| **Query Port** | `ReleasesFinder#execute` |
| **Event Port** | `Gitlab::EventStore::Event` + JSON Schema |
| **Repository Port（隐式）** | ActiveRecord 模型 API |
| **Git Port（显式封装）** | `Gitlab::Git::Repository` 公共方法 |

显式 Port 示例——Event Schema 即契约：

```ruby
class Projects::ProjectCreatedEvent < Gitlab::EventStore::Event
  def schema
    { 'properties' => { 'project_id' => { 'type' => 'integer' } }, ... }
  end
end
```

订阅方只依赖 **Schema**，不依赖 `Projects::CreateService` 内部实现。

---

## 6. 依赖方向：Core 与 Adapter 的边界

六边形架构的 **依赖规则** = 所有 Adapter 指向 Core，Core 不指向具体 Adapter 实现。

### 6.1 Primary Adapter → Core（驱动侧向内）

```
REST / GraphQL / Controller / Worker
         │
         ▼  只调用，不被回调
   CreateService#execute
         │
         ▼
      Release (Entity)
```

```ruby
# Primary：lib/api/releases.rb
::Releases::CreateService.new(...).execute   # ✓ 外层 → 内层

# Core 内不应出现：
# require 'grape'  /  include API::Helpers   # ✗ 内层 → 外层
```

**Worker 也是 Primary Adapter**：Sidekiq 框架从外驱动业务，内部仍调 Service：

```ruby
# app/workers/releases/create_evidence_worker.rb
::Releases::CreateEvidenceService.new(release, pipeline: pipeline).execute
```

### 6.2 Core → Secondary Adapter（被驱动侧向外）

Core **可以** 依赖 Secondary Adapter 的 **抽象接口**（GitLab 多为具体类封装）：

```
CreateService
    ├── release.save!                    → ActiveRecord Adapter → PostgreSQL
    ├── Tags::CreateService              → Git Adapter → Gitaly
    ├── HookData::ReleaseBuilder         → Webhook Adapter
    └── EventStore.publish(Event)        → Message Adapter → Sidekiq
```

关键：**Domain 不 import Gitaly protobuf**，只调 `Gitlab::Git::Repository#commit`。

### 6.3 Port 即依赖倒置点

| Port | 谁依赖 Port | 谁实现 Adapter |
|------|-------------|----------------|
| `CreateService#execute` | REST、GraphQL、Controller | Service 本身 |
| `Event` JSON Schema | 订阅 Worker | 发布方 Event 类 |
| `Gitlab::Git::Repository` 公共 API | Entity、Service | `lib/gitlab/git/` |

Event Port 实现 **发布方与订阅方解耦**：

```
Ci::CreatePipelineService ──publish──▶ PipelineCreatedEvent (Port 契约)
                                              ▲
MergeRequests::UpdateHeadPipelineWorker ──────┘ subscribe
```

`CreatePipelineService` 不 import `UpdateHeadPipelineWorker`——六边形 + 依赖倒置。

### 6.4 读路径的 Adapter 链

```
Controller (Primary)
  → ReleasesFinder (Core Query)
  → Release scope (Entity)
  → ReleaseSerializer / Entities::Release (Secondary 出站)
```

每一环 **只依赖下一层向内**，最后一环才序列化 outward。

### 6.5 如何验证依赖方向

在 `app/services/releases/` 中检查：

- ✗ 无 `API::Entities`、`Grape`、`ActionController` 引用
- ✓ 可引用 `app/models/`、`app/finders/`、其他 BC 的 Service
- ✓ 可引用 `lib/gitlab/git/`、`Gitlab::EventStore`（Infrastructure 封装）

---

## 7. 设计模式与 Ports/Adapters

六边形架构中，设计模式主要落在 **Adapter 实现** 与 **Core 编排** 上。

### 7.1 模式总表

| 模式 | 在六边形中的角色 | GitLab 实例 |
|------|-----------------|-------------|
| **Adapter** | Primary / Secondary 适配器本体 | `lib/api/releases.rb`、`Gitlab::Git::Repository` |
| **Port** | 交互契约（隐式或 Schema） | `Service#execute`、`Event#schema` |
| **Facade** | 简化 Core 对外接口 | `Gitlab::Git::Repository`、`Project` delegate |
| **Builder** | Secondary 出站 DTO 构建 | `HookData::ReleaseBuilder` |
| **Command** | Core 中的用例对象 | `Releases::CreateService` |
| **Query Object** | Core 中的只读 Port | `ReleasesFinder` |
| **Observer + Mediator** | 跨 Adapter 通信 | `Gitlab::EventStore` |
| **Strategy + Factory** | 多 Secondary 实现切换 | `Import::ExportStatus.for_context` |
| **Anti-Corruption Layer** | 入站外部模型翻译 | `GithubImport::Representation::*` |
| **Presenter** | UI 出站 Decorator | `Releases::LinkPresenter` |
| **Template Method** | Core 基类复用 | `Releases::BaseService` |

### 7.2 Adapter 模式（核心）

**Primary Adapter** — 协议适配：

```ruby
# HTTP world → Ruby Service world
post ':id/releases' do
  result = ::Releases::CreateService.new(user_project, current_user, declared_params(...)).execute
  present result[:release], with: Entities::Release
end
```

**Secondary Adapter** — 技术适配：

```ruby
# Domain world → Gitaly world
# lib/gitlab/git/repository.rb
def find_tag(name)
  # gRPC call hidden inside
end
```

### 7.3 Port 作为 Observer 契约

```ruby
# lib/gitlab/event_store/subscriptions/merge_requests_subscriptions.rb
store.subscribe ::MergeRequests::UpdateHeadPipelineWorker, to: ::Ci::PipelineCreatedEvent
store.subscribe ::MergeRequests::CreateApprovalEventWorker, to: ::MergeRequests::ApprovedEvent
```

每个 `*Event` 是一个 **Port 消息类型**；Worker 是 **Observer Adapter**。

### 7.4 ACL + Adapter 组合（Import）

GitHub API 是外部 **Hexagon**；GitLab Import 用双层适配：

```
GitHub JSON → Representation::Issue (ACL) → Issues::CreateService (Core) → Issue AR (Secondary DB)
```

### 7.5 测试：替换 Secondary Adapter

```ruby
# spec/services/releases/create_service_spec.rb
# 直接测 Core，mock Gitaly / Notification 等 Secondary Adapter
subject { described_class.new(project, user, params).execute }
```

这正是六边形架构 **可测试性** 的来源：Primary 换成 spec 调用，Secondary 换成 double。

---

## 8. 完整实例：创建 Release

```
[Primary]  POST lib/api/releases.rb
              │
              ▼
[Core]     Releases::CreateService#execute
              │
              ├── [Secondary] Tags::CreateService → Gitaly (tag)
              ├── [Secondary] release.save! → PostgreSQL
              ├── [Secondary] NotificationService → Email
              ├── [Secondary] HookData::ReleaseBuilder → Webhook HTTP
              ├── [Secondary] CreateEvidenceWorker → Sidekiq → PostgreSQL
              └── [Secondary] audit → Audit log
```

```
[Primary]  Sidekiq PublishEventWorker (Cron)
              │
              ▼
[Core]     Gitlab::EventStore.publish(ReleasePublishedEvent)
              │
              └── [Primary for subscriber] MergeRequests::SomeWorker ...
```

---

## 9. 与 Clean Architecture / 洋葱架构对比

| 概念 | 六边形 | Clean Architecture | GitLab |
|------|--------|------------------|--------|
| 中心 | Application Core | Entities + Use Cases | models + services |
| 外层 | Adapters | Interface Adapters + Frameworks | api/controllers/workers/lib |
| 依赖方向 | 向内 | 向内 | 向内（理想状态） |
| Port | 显式接口 | 用例边界 | Service#execute、Event schema |

三者 **可互换理解**；GitLab 文档主要用 **Bounded Context + Use Case + EventStore** 表述。

---

## 10. 测试中的 Hexagonal 收益

Spec 常 **绕过 Adapter 直接测 Core**：

```ruby
# spec/services/releases/create_service_spec.rb
subject { described_class.new(project, user, params).execute }
```

Mock Secondary Adapter（Gitaly、Notification）而测 Use Case——六边形架构可测试性的体现。

---

## 11. 关键路径速查

| Adapter 类型 | 路径 |
|--------------|------|
| REST Primary | `lib/api/` |
| GraphQL Primary | `app/graphql/` |
| Web Primary | `app/controllers/` |
| Worker Primary | `app/workers/` |
| Event Primary | `lib/gitlab/event_store/subscriptions/` |
| DB Secondary | ActiveRecord / `app/models/` |
| Git Secondary | `lib/gitlab/git/repository.rb` |
| Webhook Secondary | `lib/gitlab/hook_data/` |
| Import ACL | `lib/gitlab/github_import/representation/` |
| Application Core | `app/services/`、`app/models/` |

---

## 12. 阅读建议

1. 画 Release 创建的 Primary / Secondary Adapter 图（§8）。
2. 对照 §6 检查 `app/services/` 的 import 方向。
3. 对照 §7 模式表，定位 Adapter、Event Port、ACL。
4. 对比 `lib/api/entities/release.rb`（出站）与 `app/models/release.rb`（核心）。
5. 延伸阅读：[整洁架构 §7–§8](/posts/gitlab-clean-architecture/)、[Release 分层](/posts/gitlab-release/)。
