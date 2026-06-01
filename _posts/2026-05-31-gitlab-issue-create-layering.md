---
title: "GitLab Issue 创建：代码分层与架构原则"
date: 2026-05-31 18:00:00 +0800
categories: [GitLab, Issues, Architecture, DDD]
tags: [issue, work-items, use-case, service, adapter, bounded-context, event-store, issuable]
description: >-
  以 Issue 创建为完整用例，分析 GitLab 从 REST/GraphQL/Web 入口到 Model、Callback、Worker、EventStore 的分层组织，以及符合的 DDD 与 Clean Architecture 原则。
---

> 本文基于 GitLab 源码（`gitlab-org/gitlab`）与官方设计文档整理。  
> 分析日期：2026-05-31  
> 与 [Release 分层文档](/posts/gitlab-release/) 对照阅读效果更佳。

## 目录

1. [Issue 创建是什么](#1-issue-创建是什么)
2. [代码架构总览](#2-代码架构总览)
3. [WorkItems 限界上下文](#3-workitems-限界上下文)
4. [端到端调用链](#4-端到端调用链)
5. [各层职责详解](#5-各层职责详解)
6. [跨上下文协作](#6-跨上下文协作)
7. [符合的架构原则](#7-符合的架构原则)
8. [与 Release 创建对比](#8-与-release-创建对比)
9. [关键路径速查](#9-关键路径速查)
10. [阅读建议](#10-阅读建议)

---

## 1. Issue 创建是什么

**Issue 创建** = 用户在某个 Project 下新建一条可跟踪工作项（title、description、labels、milestone、assignees 等），并触发通知、Webhook、Todo、EventStore 等副作用。

典型入口（**同一用例，多个 Primary Adapter**）：

| 入口 | 路径 |
|------|------|
| Web UI | `POST /projects/:id/issues` → `Projects::IssuesController#create` |
| REST API | `POST /projects/:id/issues` → `lib/api/issues.rb` |
| GraphQL | `mutation createIssue` → `Mutations::Issues::Create` |
| Service Desk / 邮件 | 内部同样走 `Issues::CreateService`（`external_author` 参数） |

所有入口最终汇聚到 **`Issues::CreateService#execute`**，不在 Controller/API 里写业务逻辑。

---

## 2. 代码架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│  Primary Adapters（入站）                                         │
│  lib/api/issues.rb · GraphQL Mutations::Issues::Create          │
│  app/controllers/projects/issues_controller.rb                    │
└────────────────────────────┬────────────────────────────────────┘
                             │ params 解析、鉴权、Captcha、序列化
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Use Case（领域层）                                               │
│  Issues::CreateService  ← 权限、模板、spam、编排                   │
│    ├─ Issues::BuildService     ← 构建未持久化 Issue               │
│    └─ IssuableBaseService#create ← 共享创建模板（transaction）    │
│         └─ Issuable::Callbacks   ← Labels / Milestone / …        │
└────────────────────────────┬────────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
   app/models/issue.rb   其他 BC Service    Sidekiq Worker
   Entity + 校验          Discussions::…       NewIssueWorker
                                              Issues::PlacementWorker
         │                   │                   │
         ▼                   ▼                   ▼
   PostgreSQL          MergeRequest 等      Notification / Todo
   EventStore           限界上下文          AfterCreateService
   Webhook / Integration
```

按 [reusing_abstractions.md](https://gitlab.com/gitlab-org/gitlab/-/blob/master/doc/development/reusing_abstractions.md) 的抽象表：

| 层 | 可调用的抽象 |
|----|-------------|
| Controller / API / GraphQL | Service、Finder、Presenter、Serializer、Model 实例方法 |
| Service | Service、Finder、Model 实例方法、Worker（`perform_async`） |
| Model | 自身 + 其他 Model 方法，**不**调 Service |

Issue 创建严格遵守：**Adapter → Service → Model**，反向依赖不存在。

---

## 3. WorkItems 限界上下文

`config/bounded_contexts.yml` 中 Issue 归属 **`WorkItems`**：

```yaml
WorkItems:
  description: Issues, Epics, Tasks and WorkItems
  feature_categories:
    - team_planning
    - portfolio_management
```

命名空间映射：

| 路径 | 职责 |
|------|------|
| `app/models/issue.rb` | 聚合根 Entity（仍名 `Issue`，Work Item 类型框架） |
| `app/services/issues/` | Issue 用例（Create / Update / Close …） |
| `app/services/work_items/` | Work Item 扩展用例（继承 `Issues::CreateService`） |
| `app/services/issuable/` | Issuable 共享 Callback |
| `app/events/work_items/` | 领域事件（如 `WorkItemCreatedEvent`） |

Issue 仍是核心 Entity，但类型系统已迁移到 **Work Item Types**（`work_item_type`、`HasType` concern）。

---

## 4. 端到端调用链

以 REST API 创建 Issue 为例：

```
POST /projects/:id/issues
    │
    ├─ lib/api/issues.rb
    │     authorize! :create_issue
    │     declared_params → Issues::CreateService.new(...).execute
    │     present Entities::Issue
    │
    └─ Issues::CreateService#execute
          ├─ can?(:create_issue)                    # 用例权限
          ├─ assign_description_from_template       # 默认模板（TemplateFinder）
          ├─ Issues::BuildService#execute           # 构建 @issue（未 save）
          ├─ handle_move_between_ids                # 列表排序
          └─ IssuableBaseService#create(@issue)     # 持久化 + 副作用
                ├─ handle_quick_actions             # /assign、/label 等
                ├─ filter_params                    # 按权限删字段
                ├─ Issuable::Callbacks (Labels…)    # before_create
                ├─ transaction { issue.save! }
                ├─ Issues::CreateService#after_create
                │     ├─ spam / CRM / IssueLinks
                │     ├─ Discussions::ResolveService
                │     ├─ WorkItems::WorkItemCreatedEvent → EventStore
                │     └─ after_commit → NewIssueWorker / PlacementWorker
                └─ execute_hooks                    # Webhook 出站
```

**Web / GraphQL** 仅在参数格式与响应封装上不同，**不复制** `create` 逻辑。

---

## 5. 各层职责详解

### 5.1 Primary Adapter — REST API

```ruby
# lib/api/issues.rb
post ':id/issues' do
  authorize! :create_issue, user_project
  issue_params = declared_params(include_missing: false)
  result = ::Issues::CreateService.new(
    container: user_project,
    current_user: current_user,
    params: issue_params
  ).execute

  if result.success?
    present result[:issue], with: Entities::Issue
  else
    render_validation_error!(result[:issue]) # 或 render_api_error!
  end
end
```

Adapter 职责：**HTTP 解析、鉴权声明、调 Service、JSON 序列化、Captcha**。  
不含：label 合并逻辑、transaction、webhook。

### 5.2 Primary Adapter — GraphQL

```ruby
# app/graphql/mutations/issues/create.rb
def resolve(project_path:, **attributes)
  project = authorized_find!(project_path)
  params = build_create_issue_params(attributes.merge(author_id: current_user.id), project)
  result = ::Issues::CreateService.new(container: project, current_user: current_user, params: params).execute
  { issue: result.success? ? result[:issue] : nil, errors: result.errors }
end
```

GraphQL 额外做 **GlobalID → model_id** 转换（`milestone_id`、`assignee_ids`、`move_between_ids`），仍汇聚同一 Service。

### 5.3 Primary Adapter — Web Controller

```ruby
# app/controllers/projects/issues_controller.rb
def create
  service = ::Issues::CreateService.new(container: project, current_user: current_user, params: create_params)
  result = service.execute
  # redirect 或 JSON errors + captcha
end
```

Controller 可附加 **UI 特有** 逻辑（flash、vulnerability feedback），核心创建仍在 Service。

### 5.4 Use Case — `Issues::CreateService`

```ruby
# app/services/issues/create_service.rb
def execute(skip_system_notes: false)
  return error(_('Operation not allowed'), 403) unless @current_user.can?(authorization_action, container)

  assign_description_from_template
  @issue = @build_service.execute(initialize_callbacks: false)
  return error(@issue.errors.full_messages, 422, pass_back: { issue: @issue }) if @issue.errors.any?

  issue = create(@issue, skip_system_notes: skip_system_notes)
  issue.persisted? ? success(issue: issue) : error(...)
end
```

| 职责 | 说明 |
|------|------|
| 权限 | `:create_issue` |
| 限流 | `RateLimitedService`（`:issues_create`） |
| 构建 | 委托 `BuildService` |
| 持久化 | 继承 `IssuableBaseService#create` |
| 创建后 | `after_create` 钩子：spam、关联 Issue、Resolve discussions、EventStore |
| 异步 | `after_commit` 调度 `NewIssueWorker`、`Issues::PlacementWorker` |

返回 **`ServiceResponse`**（`success` / `error`），符合 backend-architecture 规范。

### 5.5 构建阶段 — `Issues::BuildService`

将 **「组装未保存 Issue」** 从 CreateService 拆出：

```ruby
# app/services/issues/build_service.rb
def execute(initialize_callbacks: true)
  @issue = model_klass.new(issue_params.merge(container_param)).tap do |issue|
    set_work_item_type(issue)
    initialize_callbacks!(issue) if initialize_callbacks
  end
end
```

| 写在 BuildService | 原因 |
|-------------------|------|
| `title` / `description` / `confidential` 白名单 | 公开字段 slice |
| `work_item_type` 解析与可见性 | 类型框架 |
| 从 MR discussion 生成 title/description | MR 关联用例 |
| `author` 解析（含 composite identity） | 身份模型 |

CreateService 先 Build、校验 errors，再 `create`——**早失败**，避免部分持久化。

### 5.6 共享创建模板 — `IssuableBaseService#create`

Issue、MergeRequest 等 Issuable 共享 **Template Method**：

```ruby
# app/services/issuable_base_service.rb
def create(issuable, skip_system_notes: false)
  set_issuable_author(issuable)
  handle_quick_actions(issuable)
  filter_params(issuable)              # 按权限删 assignee_ids 等

  initialize_callbacks!(issuable)
  issuable.assign_attributes(allowed_create_params(params))
  before_create(issuable)

  issuable_saved = issuable.with_transaction_returning_status do
    @callbacks.each(&:before_create)
    transaction_create(issuable)
  end

  if issuable_saved
    @callbacks.each(&:after_save_commit)
    create_system_notes(issuable, is_update: false)
    handle_changes(issuable, { params: params })
    after_create(issuable)             # 子类扩展
    execute_hooks(issuable)
    invalidate_cache_counts(issuable, ...)
  end
  issuable
end
```

**单一 transaction 边界**在 BaseService；CreateService 只 override `before_create` / `after_create`。

### 5.7 Callback — `Issuable::Callbacks::*`

横切关注点（labels、milestone、time tracking）用 **Callback 对象**，而非全堆在 CreateService：

```ruby
# issuable/callbacks/labels.rb — ALLOWED_PARAMS 白名单 + after_initialize
issuable.label_ids = compute_new_label_ids.sort
```

`Issues::BaseService#available_callbacks` 还注册 `WorkItems::Callbacks::StartAndDueDate`。

**原则**：同一 Issuable 创建/更新共享 Callback；CreateService 保持「创建 Issue」主流程可读。

### 5.8 Model — `Issue`

```ruby
# app/models/issue.rb
class Issue < ApplicationRecord
  include Issuable, Spammable, RelativePositioning, WorkItems::TypesFramework::HasType, ...
  belongs_to :project
  belongs_to :namespace
  # validates、state machine、domain methods
end
```

Model 负责：**不变量、关联、领域行为**（如 `check_for_spam` 被 Service 调用）。  
不直接调 `Issues::CreateService`（reusing_abstractions 禁止）。

### 5.9 异步 — Worker 与 `AfterCreateService`

CreateService 在 `after_commit` 入队：

```ruby
NewIssueWorker.perform_async(issue.id, user.id, issue.class.to_s)
Issues::PlacementWorker.perform_async(...)
```

`NewIssueWorker` 再调出站 Adapter / 次要用例：

```ruby
# app/workers/new_issue_worker.rb
::EventCreateService.new.open_issue(issuable, user)
::NotificationService.new.new_issue(issuable, user)
issuable.create_cross_references!(user)
Issues::AfterCreateService.new(container: issuable.project, current_user: user).execute(issuable)
```

**分工**：

| 同步（request 内） | 异步（Worker） |
|--------------------|----------------|
| save、webhook、EventStore publish | 通知、Todo、cross references |
| spam 检查、execute_hooks | `AfterCreateService`（todo、incident tracking） |

CreateService 注释明确：*Add new items to Issues::AfterCreateService if they can be performed in Sidekiq*。

### 5.10 领域事件 — EventStore

```ruby
# Issues::CreateService#publish_event
event = ::WorkItems::WorkItemCreatedEvent.new(data: { id: issue.id, namespace_id: issue.namespace_id })
issue.run_after_commit_or_now { ::Gitlab::EventStore.publish(event) }
```

事件在 **Service** 发布（非 AR callback），订阅方在其他 BC 解耦响应。

---

## 6. 跨上下文协作

CreateService 编排多个限界上下文，Model 不直接感知：

| 协作 | Service | 场景 |
|------|---------|------|
| `Tags::…` | — | Issue 创建不涉及 Git |
| `Discussions::ResolveService` | MR 讨论转 Issue | `:code_review_workflow` |
| `IssueLinks::CreateService` | 关联已有 Issue | `:team_planning` |
| `IncidentManagement::TimelineEvents::CreateService` | Incident 类型 | `:incident_management` |
| `Issues::SetCrmContactsService` | Service Desk CRM | `:service_desk` |
| `Gitlab::Template::TemplateFinder` | 默认 description 模板 | 基础设施 / 模板 |

**防腐**：MR discussion → Issue description 的转换在 `BuildService`，不污染 `Issue` Model。

---

## 7. 符合的架构原则

### 7.1 官方抽象复用规则

来源：`doc/development/reusing_abstractions.md`、`backend-architecture.md`

| 原则 | Issue 创建中的体现 |
|------|-------------------|
| **Use-case 导向** | `Issues::CreateService` = 一个完整「创建 Issue」用例，非 `Issue.create` |
| **Adapter 薄、Service 厚** | API/GraphQL/Controller 仅调 Service |
| **Service 不调 Presenter/Serializer** | 序列化在 Adapter 层 `Entities::Issue` |
| **Service 返回 ServiceResponse** | `success(issue:)` / `error(..., 422)` |
| **权限在 Service** | `can?(:create_issue)`、`filter_params` 按 ability 删字段 |
| **Worker 用 perform_async** | 不 `NewIssueWorker.new.perform` |
| **Event 在 Service 发布** | `WorkItemCreatedEvent`，非 model callback |
| **Bounded Context 命名空间** | `Issues::`、`WorkItems::` 在 `WorkItems` BC 下 |

### 7.2 Clean Architecture / 六边形

| 概念 | Issue 创建映射 |
|------|----------------|
| Entity | `Issue` |
| Use Case | `Issues::CreateService` + `IssuableBaseService#create` |
| Primary Adapter | REST / GraphQL / Controller |
| Secondary Adapter | `NotificationService`、`execute_hooks`、ActiveRecord |
| 依赖方向 | Adapter → Service → Model |

详见 [整洁架构](/posts/gitlab-clean-architecture/)、[六边形架构](/posts/gitlab-hexagonal-architecture/)。

### 7.3 DDD 战术模式

| 模式 | 体现 |
|------|------|
| **Aggregate Root** | `Issue`（labels、milestone 通过 callback 在同一 transaction） |
| **Domain Event** | `WorkItems::WorkItemCreatedEvent` |
| **Application Service** | `CreateService` |
| **Factory / Builder** | `BuildService` 构建未持久化聚合 |
| **Template Method** | `IssuableBaseService#create` |
| **Strategy / Callback** | `Issuable::Callbacks::Labels` 等 |

### 7.4 SOLID 与扩展

| 原则 | 体现 |
|------|------|
| **OCP** | `Issues::CreateService.prepend_mod` / EE 扩展 `after_create` |
| **SRP** | Build vs Create vs AfterCreate vs Callback 拆分 |
| **DIP** | Controller 依赖 `CreateService` 接口（`#execute`），不依赖 ActiveRecord 细节 |

`WorkItems::CreateService < Issues::CreateService` — 子用例继承并替换 `BuildService`，复用创建管线。

---

## 8. 与 Release / Project 创建对比

| 维度 | Issue 创建 | Release 创建 | Project 创建 |
|------|-----------|--------------|--------------|
| Bounded Context | `WorkItems` | `Releases` | `Projects` |
| 返回值 | `ServiceResponse` | `ServiceResponse` | `Project`（老风格） |
| 构建拆分 | `BuildService` + `create` | 内联 `build_release` | 单 Service 内 `Project.new` |
| 外部 Git | 无 | `Tags::CreateService` | `create_repository` → Gitaly |

Release 创建完整分析见 [Release 创建分层](/posts/gitlab-release-create-layering/)。  
Project 创建完整分析见 [Project 创建分层](/posts/gitlab-project-create-layering/)。

**共同点**：Adapter 薄、Service 编排、Model 守规则、EventStore 解耦；子用例（模板/Import）拆独立 Service。

---

## 9. 关键路径速查

| 类别 | 路径 |
|------|------|
| Bounded Context | `config/bounded_contexts.yml` → `WorkItems:` |
| 设计指南 | `doc/development/software_design.md`、`reusing_abstractions.md` |
| 聚合根 | `app/models/issue.rb` |
| **创建用例** | `app/services/issues/create_service.rb` |
| 构建 | `app/services/issues/build_service.rb` |
| 共享创建模板 | `app/services/issuable_base_service.rb` |
| Callback | `app/services/issuable/callbacks/` |
| Work Item 扩展 | `app/services/work_items/create_service.rb` |
| **REST 入口** | `lib/api/issues.rb` |
| **GraphQL 入口** | `app/graphql/mutations/issues/create.rb` |
| **Web 入口** | `app/controllers/projects/issues_controller.rb` |
| 异步 | `app/workers/new_issue_worker.rb`、`app/services/issues/after_create_service.rb` |
| 领域事件 | `app/events/work_items/work_item_created_event.rb` |
| 权限 | `app/policies/issue_policy.rb` |
| Spec | `spec/services/issues/create_service_spec.rb` |

---

## 10. 阅读建议

1. **从 Adapter 跟到 Service**：`lib/api/issues.rb` POST → `CreateService#execute`。
2. **读 `IssuableBaseService#create`**：理解 Issue/MR 共用的创建管线。
3. **对比 Build 与 Create**：为何先 `BuildService` 再 `create`。
4. **看 `after_create` + `NewIssueWorker`**：同步 vs 异步副作用边界。
5. **跑 spec**：`bundle exec rspec spec/services/issues/create_service_spec.rb`。

**延伸阅读**：[Release 分层](/posts/gitlab-release/) · [Model/Service 分工](/posts/gitlab-release/#55-model-与-service-的分工) · [DDD 战略模式](/posts/gitlab-ddd-strategic-patterns/)
