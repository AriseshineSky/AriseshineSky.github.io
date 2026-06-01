---
title: "整洁架构（Clean Architecture）在 GitLab 中的映射"
date: 2026-05-31 16:30:00 +0800
categories: [GitLab, Architecture]
tags: [clean-architecture, dependency-rule, use-case, entity, adapter]
description: >-
  用 GitLab 源码说明 Clean Architecture 的同心圆分层、依赖规则，以及 Entity、Use Case、Interface Adapter 在 Rails 模块化单体中的 pragmatic 实现。
---

> 参考 Robert Martin 的 Clean Architecture（同心圆 + 依赖规则）。  
> GitLab 并非严格分层目录，而是 **Rails 惯例 + Bounded Context** 的务实映射。

## 1. Clean Architecture 核心

### 1.1 同心圆（由外到内）

```
┌─────────────────────────────────────────┐
│  Frameworks & Drivers                    │  ← DB、Web、Sidekiq、Gitaly
│  ┌───────────────────────────────────┐  │
│  │  Interface Adapters                │  │  ← Controller、API、Presenter
│  │  ┌─────────────────────────────┐  │  │
│  │  │  Use Cases (Application)     │  │  │  ← Service Object
│  │  │  ┌───────────────────────┐  │  │  │
│  │  │  │  Entities (Enterprise) │  │  │  │  ← Domain Model
│  │  │  └───────────────────────┘  │  │  │
│  │  └─────────────────────────────┘  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### 1.2 依赖规则（Dependency Rule）

**源码依赖只能指向内层**。外层知道内层，内层不知道外层。

- Entity 不 import Controller
- Use Case 不 import Grape Entity
- 框架细节（ActiveRecord、Sidekiq）在最外层或通过抽象隔离

---

## 2. GitLab 分层映射

| Clean Architecture 层 | GitLab 实现 | 典型路径 |
|----------------------|-------------|----------|
| **Entities** | ActiveRecord Model + PORO | `app/models/release.rb`、`app/models/releases/source.rb` |
| **Use Cases** | Service Object | `app/services/releases/create_service.rb` |
| **Interface Adapters（入）** | Controller、REST API、GraphQL | `lib/api/releases.rb`、`app/graphql/mutations/` |
| **Interface Adapters（出）** | Serializer、Presenter、Hook Builder | `lib/api/entities/`、`app/presenters/` |
| **Frameworks & Drivers** | Rails、PostgreSQL、Sidekiq、Gitaly | `config/`、`lib/gitlab/git/` |

GitLab 官方文档（`doc/development/software_design.md`）区分：

- **Domain layer**：`app/models`、`app/services`、领域相关 `lib/`
- **Application adapters**：Controller、API（**不受** bounded context 强制）
- **Infrastructure**：通用 `lib/`、未来提取为 `gems/`

---

## 3. Entities 层

### 3.1 持久化 Entity

```ruby
# app/models/release.rb — Enterprise Business Rules
class Release < ApplicationRecord
  validates :tag, uniqueness: { scope: :project_id }
  validate :sha_unchanged, on: :update

  def upcoming_release?
    released_at.present? && released_at.to_i > Time.zone.now.to_i
  end
end
```

Entity 封装 **不变量** 和 **领域行为**，不依赖 HTTP 或 JSON。

### 3.2 PORO Entity / Value Object

```ruby
# app/models/releases/source.rb — 无框架持久化
module Releases
  class Source
    include ActiveModel::Model
    def url
      Gitlab::Routing.url_helpers.project_archive_url(...)
    end
  end
end
```

---

### 3.3 Model 与 Service 的分工

Clean Architecture 中 **Entities** 与 **Use Cases** 是相邻的两层，GitLab 用 `app/models/` 与 `app/services/` 对应。判断标准：

| | Model（Entity） | Service（Use Case） |
|---|-----------------|---------------------|
| **职责** | 对象是什么、守什么规则 | 一个完整业务动作怎么执行 |
| **依赖** | 尽量只依赖自身字段/关联 | 可编排多个 Model、其他 Service、Finder |
| **副作用** | 无跨系统编排 | 通知、Webhook、Worker、Event、Audit |
| **权限** | 不含用例级权限 | `Ability.allowed?` 等前置检查 |
| **事务** | 单对象 save 可发生在 Service 内 | `transaction` 边界在 Service |

**写在 Model ✓**

- 校验、不变量（`validates`、`validate`）
- 基于自身属性的方法（`upcoming_release?`、`name` fallback）
- 关联、`scope`、enum
- PORO 值对象式计算（`Releases::Source#url`）

**写在 Service ✓**

- `#execute` 编排完整用例
- 权限与前置条件
- 跨 Bounded Context 调用（`Tags::CreateService`）
- 副作用链（通知 + webhook + Worker + audit）
- `ApplicationRecord.transaction`
- API 参数白名单（`Links::Params`）

**写在 Finder ✓** — 复杂只读查询（`ReleasesFinder`）。

**写在 Adapter ✓** — HTTP/JSON（`lib/api/entities/`、Presenter）。

Release 完整对照表与决策流程见 [Release 文档 §5.5](/posts/gitlab-release/#55-model-与-service-的分工)。

---

### 3.4 Client 与 Service 的分工

Clean Architecture 最外圈 **Frameworks & Drivers** 里，GitLab 用 **Client**（`lib/gitlab/**/client.rb`）对接 Gitaly、GitHub、K8s 等；**Use Case** 仍对应 `app/services/`。

| | Client（出站基础设施） | Service（Use Case） |
|---|------------------------|---------------------|
| **职责** | 怎么连、怎么发请求、怎么重试 | 何时调、权限、编排、业务错误 |
| **位置** | `lib/gitlab/gitaly_client/`、`lib/gitlab/github_import/client.rb` | `app/services/releases/` |
| **依赖** | gRPC/HTTP SDK、protobuf | Model、Finder、其他 Service、`repository` 封装 |
| **不含** | 权限、Webhook、Audit、用例编排 | gRPC 请求体、channel 配置、API 限流实现 |

Service 通常 **不直接** `new GitalyClient`，而调 `Gitlab::Git::Repository`（Interface Adapter 封装 Client）。

完整示例、Release 调用链与决策流程见 [Release 文档 §5.6](/posts/gitlab-release/#56-client-与-service-的分工)。

---

## 4. Use Cases 层

Use Case = 应用特定的 **业务规则 + 编排**。

```ruby
# app/services/releases/create_service.rb
module Releases
  class CreateService < BaseService
    def execute
      return error(...) unless allowed?           # 应用级权限规则
      evidence_pipeline = EvidencePipelineFinder.new(...).execute
      tag = ensure_tag
      create_release(tag, evidence_pipeline)      # 编排 Entity + 外部 Service
    end
  end
end
```

**依赖方向**（符合依赖规则）：

```
CreateService  →  Release (Entity)
              →  Tags::CreateService (其他 Use Case)
              →  EvidencePipelineFinder (Query)
              ✗  不依赖 lib/api/entities/release.rb
```

Controller/API 依赖 Service；Service 不依赖 API DTO。

**另一完整示例**：Issue / Project / Release 创建分别见 `Issues::CreateService`、`Projects::CreateService`、`Releases::CreateService`。详见 [Issue 创建分层](/posts/gitlab-issue-create-layering/) · [Project 创建分层](/posts/gitlab-project-create-layering/) · [Release 创建分层](/posts/gitlab-release-create-layering/)。

---

## 5. Interface Adapters 层

### 5.1 入站适配器（Driving Adapters）

将外部输入转为 Use Case 调用：

```ruby
# lib/api/releases.rb
post ':id/releases' do
  authorize_create_release!
  result = ::Releases::CreateService
    .new(user_project, current_user, declared_params(...))
    .execute

  if result[:status] == :success
    present result[:release], with: Entities::Release
  else
    render_api_error!(result[:message], result[:http_status])
  end
end
```

```ruby
# app/graphql/mutations/releases/create.rb
result = ::Releases::CreateService.new(project, current_user, params).execute
```

**同一 Use Case，多个 Adapter**——Clean Architecture 的典型特征。

### 5.2 出站适配器（Driven Adapters — 展示）

Entity → 外部世界所需的格式：

```ruby
# lib/api/entities/release.rb — 不是 Domain Entity！
module API
  module Entities
    class Release < BasicReleaseDetails
      expose :author, using: Entities::UserBasic
      expose :assets do
        expose :sorted_links, as: :links, using: Entities::Releases::Link
      end
    end
  end
end
```

```ruby
# lib/gitlab/hook_data/release_builder.rb — Webhook DTO
def build(action)
  { object_kind: 'release', action: action, assets: { ... } }
end
```

### 5.3 Presenter（视图适配）

```ruby
# app/presenters/releases/link_presenter.rb
def direct_asset_url
  return @subject.url unless @subject.filepath
  release.download_url(@subject.filepath)
end
```

---

## 6. Frameworks & Drivers 层

### 6.1 数据库（ActiveRecord Driver）

```ruby
Release.save!   # Entity 使用 AR，但 Use Case 编排 save 时机
```

GitLab **没有** Repository 接口层；ActiveRecord 即 persistence framework。

### 6.2 Gitaly（外部 Git 服务 Driver）

```ruby
# lib/gitlab/git/repository.rb — 封装 Gitaly RPC
module Gitlab
  module Git
    class Repository
      include Gitlab::Git::WrapsGitalyErrors
      # commit、find_tag、branch_names ...
    end
  end
end
```

Domain 通过 `project.repository` 访问 Git，不直接调 Gitaly protobuf—— **Infrastructure 封装在 lib/gitlab/git/**。

### 6.3 Sidekiq（异步 Driver）

```ruby
# app/workers/releases/create_evidence_worker.rb
def perform(release_id, pipeline_id = nil)
  ::Releases::CreateEvidenceService.new(release, pipeline: pipeline).execute
end
```

Worker 是框架入口，内部仍调用 Use Case（依赖向内）。

---

## 7. 内外层依赖关系详解

依赖规则不是目录名，而是 **谁 import 谁、谁调用谁**。在 GitLab 里主要靠调用方向体现。

### 7.1 总览：四层依赖链

```
┌─────────────────────────────────────────────────────────┐
│ 外层 Frameworks & Drivers + Interface Adapters           │
│  lib/api/  app/controllers/  app/workers/               │
│  lib/gitlab/git/  lib/gitlab/hook_data/                 │
└───────────────────────────┬─────────────────────────────┘
                            │ 只向内调用，不被内层引用
                            ▼
┌─────────────────────────────────────────────────────────┐
│ 内层 Use Cases                                           │
│  app/services/releases/create_service.rb                │
│  app/finders/releases_finder.rb                          │
└───────────────────────────┬─────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│ 更内层 Entities                                          │
│  app/models/release.rb  app/models/releases/source.rb   │
└───────────────────────────┬─────────────────────────────┘
                            │ 经 Adapter 访问外部
                            ▼
┌─────────────────────────────────────────────────────────┐
│ 出站 Secondary Adapters / Infrastructure               │
│  ActiveRecord→PG  Git::Repository→Gitaly  EventStore    │
└─────────────────────────────────────────────────────────┘
```

### 7.2 写操作：依赖由外向内

```ruby
# ① 外层 REST Adapter
# lib/api/releases.rb
result = ::Releases::CreateService.new(user_project, current_user, params).execute

# ② 内层 Use Case — 不 import lib/api/entities/
# app/services/releases/create_service.rb
release.save!
release.execute_hooks('create')

# ③ 更内层 Entity
# app/models/release.rb
def execute_hooks(action)
  Gitlab::HookData::ReleaseBuilder.new(self).build(action)
end
```

**识别方法**：在 `app/services/` 中搜索 `API::Entities` 或 `Grape`——理想情况下 **不应出现**。

### 7.3 读操作：同样向内

```
GET /releases
  → lib/api/releases.rb              （外层）
  → ReleasesFinder#execute           （内层 Query）
  → Release.for_projects(...).tagged （Entity scope）
  → Entities::Release                （出站 Adapter，最外层）
```

Finder 不依赖 Controller；Controller 依赖 Finder——符合依赖规则。

### 7.4 多入口、单核心

```ruby
# GraphQL Adapter
Releases::CreateService.new(project, current_user, params).execute

# REST Adapter
Releases::CreateService.new(user_project, current_user, params).execute
```

两个外层 Adapter 依赖 **同一个** 内层 Use Case；Use Case 不知道 HTTP 还是 GraphQL。

### 7.5 出站：内层经 Adapter 访问基础设施

内层不直接绑 Gitaly protobuf，而经封装层：

```
Release#commit
  → project.repository
  → Gitlab::Git::Repository    # lib/gitlab/git/ — Secondary Adapter
  → Gitaly RPC                 # Infrastructure
```

Webhook 同理：`Release` → `HookData::ReleaseBuilder` → HTTP payload。

### 7.6 跨上下文：Event 作为向内契约（依赖倒置）

```ruby
# Ci 用例发布事件 — 不依赖 MR Worker
Gitlab::EventStore.publish(
  Ci::PipelineCreatedEvent.new(data: { pipeline_id: pipeline.id })
)

# MR 上下文订阅 — 依赖 Event Schema，不依赖 CreatePipelineService
store.subscribe ::MergeRequests::UpdateHeadPipelineWorker, to: ::Ci::PipelineCreatedEvent
```

发布方 **不知道** 订阅方列表——比 `perform_async(UpdateHeadPipelineWorker)` 更符合 **依赖倒置 + 开闭原则**。

### 7.7 如何在代码里判断内外层

| 判断方式 | 外层 | 内层 |
|----------|------|------|
| 路径 | `lib/api/`、`app/controllers/`、`app/graphql/` | `app/services/`、`app/models/` |
| import 方向 | 引用 Service、Finder | 不引用 API Entity、Controller |
| BC 约束 | 应用层 **不受** bounded context 强制 | 必须在 `Releases::` 等 BC 内 |
| 职责 | 协议、序列化、鉴权入口 | 规则、编排、不变量 |

### 7.8 GitLab 的 pragmatic 妥协

| 理想 | GitLab 现实 |
|------|-------------|
| Entity 纯 Ruby，Repository 持久化 | `Release < ApplicationRecord` 直接 `save!` |
| Domain 零框架依赖 | Entity 使用 Rails validation、enum、callback |
| 严格 Repository 接口 | ActiveRecord + Finder 替代 |

`Release#execute_hooks` 在 Entity 内调 Hook Builder，是 **内层略向出站 Adapter 依赖** 的妥协，但 API → Service → Model 的主链仍然清晰。

### 7.9 常见违反（仍在治理中）

| 违反 | 示例 | GitLab 对策 |
|------|------|-------------|
| Entity 堆业务 | `Project` 4000+ 行 | Taming Omniscient Classes 指南 |
| Controller 写业务 | legacy code | 迁移到 Service |
| God Worker | `PostReceive` | EventStore 解耦 |
| Use Case 直接 perform 其他域 Worker | 旧 CI 代码 | 改为 publish Event |

---

## 8. 设计模式在 Clean Architecture 中的体现

GoF / 企业模式在 GitLab 中 **按层分布**，共同支撑「依赖向内」。

### 8.1 按架构层归类

| 层 | 常见设计模式 | GitLab 实例 |
|----|-------------|-------------|
| **Entity** | State、Strategy（enum） | `Release#upcoming_release?`、`Link#link_type` enum |
| **Use Case** | Command、Template Method | `CreateService#execute`、`BaseService` 共享逻辑 |
| **Query** | Query Object | `ReleasesFinder#execute` |
| **入站 Adapter** | Adapter | `lib/api/releases.rb` 适配 HTTP → Service |
| **出站 Adapter** | Adapter、Builder、Facade | `HookData::ReleaseBuilder`、`Gitlab::Git::Repository` |
| **跨上下文** | Observer、Mediator | `Gitlab::EventStore` pub-sub |
| **Import** | Anti-Corruption Layer、Factory | `GithubImport::Representation::*`、`ExportStatus.for_context` |
| **展示** | Decorator/Presenter | `Releases::LinkPresenter#direct_asset_url` |

### 8.2 Command 模式 → Service Object

每个 Use Case 是一个 Command，统一入口 `#execute`：

```ruby
module Releases
  class CreateService < BaseService
    def execute
      # 前置条件 + 编排 + 返回 ServiceResponse
    end
  end
end
```

Controller/API **只发 Command**，不包含业务分支。

### 8.3 Template Method → BaseService

```ruby
# app/services/releases/base_service.rb
class BaseService
  def milestones
    MilestonesFinder.new(...).execute  # 子类复用的算法骨架
  end

  def execute_hooks(release, action = 'create')
    release.execute_hooks(action)
  end
end
```

`CreateService` / `UpdateService` 共享 tag、milestone、hook 逻辑——Template Method 在 Use Case 层复用。

### 8.4 Adapter 模式 → Interface Adapters

**入站**：HTTP 参数 → Ruby Hash → Service

```ruby
# lib/api/releases.rb
result = ::Releases::CreateService.new(user_project, current_user, declared_params(...)).execute
present result[:release], with: Entities::Release  # 出站 Adapter
```

**出站（Git）**：Gitaly protobuf → `Gitlab::Git::Repository` 领域 API

```ruby
# lib/gitlab/git/repository.rb
module Gitlab
  module Git
    class Repository
      include Gitlab::Git::WrapsGitalyErrors
      def commit(sha); end  # 隐藏 gRPC 细节
    end
  end
end
```

### 8.5 Builder 模式 → 出站 DTO

```ruby
# lib/gitlab/hook_data/release_builder.rb
def build(action)
  {
    object_kind: 'release',
    action: action,
    assets: { links: release.links.map(&:hook_attrs), ... }
  }
end
```

Builder 把 Entity 转为外部系统格式，Entity 不拼 Hash 字段。

### 8.6 Strategy + Factory Method → Import

```ruby
# app/models/import/export_status.rb — Factory
def self.for_context(pipeline_tracker, relation)
  if pipeline_tracker.entity.bulk_import.offline_export?
    Import::Offline::ExportStatus.new(...)
  else
    ::BulkImports::ExportStatus.new(...)
  end
end

# 抽象基类 — Template Method + Strategy
def in_progress?
  raise Gitlab::AbstractMethodError  # 子类实现不同策略
end
```

同一概念（导出状态），不同导入场景 **策略切换**，调用方只依赖抽象接口。

### 8.7 Observer / Mediator → EventStore

```ruby
# 发布（Subject）
Gitlab::EventStore.publish(Ci::PipelineCreatedEvent.new(...))

# 订阅（Observer）
store.subscribe MergeRequests::UpdateHeadPipelineWorker, to: Ci::PipelineCreatedEvent
```

EventStore 充当 **Mediator**：发布方与订阅方互不直接引用。

### 8.8 Facade 模式 → 聚合根 API

```ruby
# app/models/project.rb（节选）
with_options to: :project_setting do
  delegate :squash_option, :squash_option=
end
```

`Project` 作为 Facade 隐藏 `ProjectSetting` 内部结构——官方文档也将其作为 **Taming Omniscient Classes** 的过渡手段。

`Gitlab::Git::Repository` 同样是 Facade：对上层隐藏 Gitaly 复杂性。

### 8.9 Presenter / Decorator → 视图适配

```ruby
# app/presenters/releases/link_presenter.rb
def direct_asset_url
  return @subject.url unless @subject.filepath
  release.download_url(@subject.filepath)
end
```

在不改 Entity 的前提下，为 UI/API 增加展示逻辑。

### 8.10 Anti-Corruption Layer → Import Representation

```ruby
# lib/gitlab/github_import/representation/issue.rb
def self.from_api_response(issue, additional_data = {})
  { iid: issue[:number], title: issue[:title], state: issue[:state] == 'open' ? :opened : :closed }
end
```

外部 GitHub 模型 **不直接进入** GitLab Entity，先经 ACL 翻译。

### 8.11 设计模式与依赖方向

| 模式 | 依赖方向 |
|------|----------|
| Command / Service | 外层 Adapter → Use Case |
| Adapter（入站） | HTTP → Core |
| Adapter（出站） | Core → Infrastructure |
| EventStore | 发布方 ⊥ 订阅方（经 Event Schema 耦合） |
| ACL | 外部模型 → 内部 DTO → Core |

---

## 9. 与 DDD / 六边形的关系

| 架构 | 与 Clean Architecture 关系 |
|------|---------------------------|
| **DDD** | Entities + Use Cases 概念重叠；DDD 增加 Bounded Context |
| **Hexagonal** | Interface Adapters = Ports & Adapters 层 |
| **Onion** | 几乎同构，强调 Domain 在中心 |

GitLab 同时运用：**Clean 的分层思想 + DDD 的上下文拆分 + Hexagonal 的多 Adapter**。

---

## 10. 读/写路径对照

### 读（Query）

```
GET /releases
  → Adapter: lib/api/releases.rb
  → Finder: ReleasesFinder          ← 可视为 Use Case 的只读变体
  → Entity: Release scope
  → Adapter: Entities::Release → JSON
```

### 写（Command）

```
POST /releases
  → Adapter: lib/api/releases.rb
  → Use Case: CreateService
  → Entity: Release.save!
  → Adapter: HookData::ReleaseBuilder → Webhook
  → Driver: Sidekiq Worker
```

---

## 11. 关键路径速查

| 层 | 路径 |
|----|------|
| Entity | `app/models/` |
| Use Case | `app/services/<context>/` |
| Query | `app/finders/` |
| REST Adapter | `lib/api/` |
| GraphQL Adapter | `app/graphql/` |
| Web Adapter | `app/controllers/` |
| 出站 DTO | `lib/api/entities/`、`lib/gitlab/hook_data/` |
| Infrastructure | `lib/gitlab/git/`、`app/workers/` |
| 设计指南 | `doc/development/software_design.md` |

---

## 12. 阅读建议

1. 选一个 API endpoint，从 `lib/api/` 追到 `app/services/`，确认 **Adapter 不含业务逻辑**（§7）。
2. 区分 `app/models/issue.rb`（Entity）与 `lib/api/entities/issue.rb`（DTO Adapter）。
3. 对照 §8 设计模式表，在源码里定位 Adapter、Builder、EventStore。
4. 读 [Release §5.5](/posts/gitlab-release/#55-model-与-service-的分工) 理解 Model 与 Service 如何分工。
5. 读 `doc/development/software_design.md#design-software-around-use-cases-not-entities`。
6. 结合 [Release 文档](/posts/gitlab-release/) 与 [六边形架构](/posts/gitlab-hexagonal-architecture/) 交叉阅读。
