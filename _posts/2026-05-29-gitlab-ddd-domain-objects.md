---
title: "GitLab 中的 DDD 概念与 Project 示例"
date: 2026-05-29 10:00:00 +0800
categories: [GitLab, DDD]
tags: [domain-driven-design, project, aggregate, bounded-context, value-object]
description: >-
  基于 GitLab 代码库目录结构与官方设计文档，理解 DDD 战术模式在 Rails 模块化单体中的映射，以 Project 为例。
---

> 本文档基于 GitLab 代码库的目录结构、文件名及官方设计文档整理，用于理解 GitLab 如何将 DDD（领域驱动设计）战术模式映射到 Rails 模块化单体架构中。  
> 分析日期：2026-05-29

## 1. 核心结论

GitLab **没有**采用 textbook DDD 的分层目录（如 `domain/entities/`、`domain/value_objects/`），而是：

1. 用 **Ruby 命名空间（Bounded Context）** 组织领域代码；
2. 用 **ActiveRecord Model** 承载大部分持久化 Entity；
3. 用 **Service / Finder / Event** 等 Rails 惯用法补位；
4. 用 **EventStore** 做跨 Bounded Context 解耦。

`Project` 在 GitLab 中是一个典型的 **容器型 Entity（omniscient class）**：它关联大量子资源，但 GitLab 官方设计指南明确要求——**与 Project 生命周期强相关的行为** 才放在 `Projects::` 命名空间下；仓库、CI、Issue 等特性应归属各自 Bounded Context，而不是全部堆在 `Project` 类上。

`config/bounded_contexts.yml` 中对 `Projects::` 的定义：

> Managing projects as workspaces and their lifecycle. **Feature specific behavior must not go here.**

---

## 2. DDD 概念对照总表

| DDD 概念 | GitLab 实现 | 规模（约） | Project 示例 |
|----------|-------------|------------|--------------|
| **Entity** | ActiveRecord + namespaced model | 232 顶层 + 83 子目录 | `Project`、`ProjectSetting`、`ProjectFeature`、`Projects::BranchRule` |
| **Value Object** | PORO、FixedItemsModel、`app/enums/` | 无统一 `ValueObject` 基类 | `Projects::Forks::Details`、visibility 枚举、`ProjectImportData` 中的结构化数据 |
| **Aggregate Root** | 隐式；无显式 Aggregate 类 | — | `Project` 作为 workspace 根；子 aggregate 分散（如 `Repositories::`、`Ci::`） |
| **Domain Service** | `app/services/<context>/` | 128 个 service 目录 | `Projects::CreateService`、`Projects::TransferService`、`Projects::ArchiveService` |
| **Repository** | 基本没有；直接用 AR + Finder | 194 个 finder | `ProjectsFinder`、`GroupProjectsFinder`、`Projects::BranchRulesFinder` |
| **Domain Event** | `app/events/` + `Gitlab::EventStore` | 51 个 event 类 | `Projects::ProjectCreatedEvent`、`Projects::ProjectDeletedEvent` |
| **Factory / Builder** | `lib/gitlab/data_builder/`、`import/representation/`、`hook_data/` | 按场景分散 | `Gitlab::ImportExport::Project::ObjectBuilder`、`Gitlab::HookData::ProjectBuilder` |

---

## 3. Bounded Context：战略设计基础

### 3.1 注册与强制

| 机制 | 路径 | 说明 |
|------|------|------|
| Bounded Context 注册表 | `config/bounded_contexts.yml` | 定义允许的顶层命名空间 |
| RuboCop 强制 | `Gitlab/BoundedContexts` | 新类必须落在某个 bounded context 下 |
| 设计指南 | `doc/development/software_design.md` | Ubiquitous Language、God Object 治理等 |

### 3.2 Project 所在的 Context

`Project` 属于 **`Projects::`** Bounded Context，但该 context **只负责 workspace 生命周期**，不负责特性逻辑：

```
Projects::                    ← Project 生命周期（创建、转移、归档、删除）
├── CreateService
├── TransferService
├── ArchiveService
└── ProjectCreatedEvent

Repositories::                ← 仓库相关（不应放在 Projects:: 下）
Ci::                          ← CI/CD（Project 只是 tenant 引用）
Issuables:: / WorkItems::     ← Issue、MR、Work Item
MergeRequests::               ← MR 特有逻辑
```

**设计原则**：`Project` 是 tenant 容器；Repository、Runner、Pipeline 等是独立 Bounded Context 中的概念，通过 `project_id` 关联，而非嵌套在 `Projects::` 命名空间下。

---

## 4. 各 DDD 概念详解（以 Project 为例）

### 4.1 Entity — 持久化领域对象

**GitLab 实现**：`app/models/` 下的 ActiveRecord 类，有唯一 ID，可持久化，代表业务中的"事物"。

**Project 相关 Entity 目录结构**：

```
app/models/
├── project.rb                          # 核心 Entity（omniscient class）
├── project_setting.rb                  # 项目设置
├── project_feature.rb                  # 功能开关（issues、wiki、snippets 等）
├── project_ci_cd_setting.rb            # CI/CD 设置
├── project_repository.rb               # 仓库元数据（非 Git 对象本身）
├── project_group_link.rb               # 与 Group 的共享关系
├── project_authorization.rb            # 授权记录
├── project_import_state.rb             # 导入状态
├── project_export_job.rb               # 导出任务
├── project_deploy_token.rb             # Deploy token 关联
├── project_pages_metadatum.rb          # Pages 元数据
├── project_auto_devops.rb              # Auto DevOps 配置
├── project_daily_statistic.rb          # 日统计
├── project_label.rb                    # 项目 Label
├── project_snippet.rb                  # Snippet
├── project_wiki.rb                     # Wiki
├── project_team.rb                     # 团队成员（非 AR，见下文）
└── projects/                           # namespaced 子 Entity
    ├── branch_rule.rb
    ├── branch_rules.rb
    ├── project_topic.rb
    ├── sync_event.rb
    ├── repository_storage_move.rb
    ├── data_transfer.rb
    ├── build_artifacts_size_refresh.rb
    └── import_export/
        ├── relation_export.rb
        └── relation_import_tracker.rb
```

**Schema 文档**（Entity 的数据契约）：

```
db/docs/
├── projects.yml
├── project_settings.yml
├── project_features.yml
├── project_ci_cd_settings.yml
├── project_repositories.yml
└── ...
```

**Concern 复用领域行为**：

```
app/models/concerns/
├── projects/
│   ├── custom_branch_rule.rb
│   ├── squash_option.rb
│   └── target_projects.rb
├── update_project_statistics.rb
├── cascading_project_setting_attribute.rb
├── project_features_compatibility.rb
└── select_for_project_authorization.rb
```

**EE 扩展**（同一 Entity 的分层扩展）：

```
ee/app/models/
├── ee/project.rb                       # prepend 到 CE Project
└── projects/
    ├── all_protected_branches_rule.rb
    ├── branch_rules/
    └── compliance_standards/
```

**要点**：

- `Project` 是历史遗留的顶层 omniscient class（>1000 LOC），官方指南建议新行为放入 dedicated class，而非继续往 `Project` 上堆方法。
- 子 Entity 如 `ProjectSetting`、`ProjectFeature` 通过外键关联，分担 `Project` 的数据与职责。
- `Projects::BranchRule` 等 namespaced model 代表较新的代码风格。

---

### 4.2 Value Object — 无独立身份的值对象

**GitLab 实现**：没有统一的 `ValueObject` 基类，而是通过以下形式表达：

| 形式 | 路径模式 | Project 示例 |
|------|----------|--------------|
| PORO（Plain Old Ruby Object） | `app/models/<context>/` 或 `lib/gitlab/<context>/` | `Projects::Forks::Details` |
| FixedItemsModel | `gems/activerecord-gitlab/` | 静态配置型对象（Project 本身不用，Work Item 类型常用） |
| Enum | `app/enums/`、`app/models/concerns/enums/` | visibility level、access level 等 |
| 结构化嵌入字段 | Entity 内的 JSON/结构化属性 | `ProjectImportData` |

**典型示例：`Projects::Forks::Details`**

```
app/models/projects/forks/details.rb
```

- 无独立数据库表；
- 封装 fork 与 source project 的分叉计算逻辑（ahead/behind counts）；
- 通过 `initialize(project, ref)` 构造，生命周期绑定于一次计算；
- 符合 Value Object 特征：**无 ID、不可变语义、描述一个计算结果**。

**Enum 示例**：

Project 的 visibility、各 feature 的 access level 等，通常以 Rails `enum` 或 concern 中的常量定义，而非独立 Value Object 类。GitLab 的 `app/enums/` 目录目前文件较少（主要在 EE 的 `Vulnerabilities::`、`Security::` 下），大量 enum 仍分散在 model concern 中。

**官方文档中的 Value Object 范例**（非 Project，但说明模式）：

- `Ci::Minutes::Usage` — 计算用量
- `DesignManagement::DesignAtVersion` — 组合 design + version

Project 领域可类比：`Projects::Forks::Details` 是对 fork 关系的值对象式封装。

Project 相关的 enum 与常量取值是 Value Object 最集中的区域，详见 [第 11 章](#11-project-相关-enum-与-value-object-专章)。

---

### 4.3 Aggregate Root — 聚合根（隐式）

**GitLab 实现**：**没有显式的 Aggregate 类或 Aggregate Root 基类**。聚合边界通过以下方式隐式表达：

| 机制 | Project 场景 |
|------|--------------|
| 核心 Entity 作为根 | `Project` 是 workspace 聚合根，关联多个子 Entity |
| 子 Entity 外键 | `project_settings.project_id`、`project_features.project_id` 等 |
| Domain Service 协调 | `Projects::CreateService` 在一个事务中创建 Project + 关联对象 |
| Domain Event 通知外部 | `Projects::ProjectCreatedEvent` 发布后，其他 context 各自响应 |
| 禁止跨 aggregate 直接修改 | 通过 Service + Event 而非直接调用其他 context 的内部逻辑 |

**Project 聚合结构（简化）**：

```
Project (Aggregate Root — workspace 层面)
├── ProjectSetting
├── ProjectFeature
├── ProjectCiCdSetting
├── ProjectRepository (元数据)
├── ProjectGroupLink
├── ProjectAuthorization
└── ... (lifecycle 相关的直接子对象)

NOT in Project aggregate (独立 Bounded Context):
├── Repository (Git 对象)     → Repositories::
├── Ci::Pipeline              → Ci::
├── Issue / MergeRequest      → Issuables:: / MergeRequests::
├── Pages::Domain             → Pages::
└── Packages                  → Packages::
```

**对比 Work Item**（GitLab 中较清晰的 aggregate 示例）：

```
WorkItem (隐式 Aggregate Root)
├── WorkItems::Type
├── WorkItems::Widgets::*     (Description, Assignees, Labels, ...)
└── WorkItems::Transition
```

Project 的 aggregate 边界更模糊，因为它是 **tenant 容器** 而非单一业务概念。GitLab 通过 Bounded Context 拆分来避免 Project aggregate 无限膨胀。

`Project` + `ProjectSetting` 是 workspace 聚合中最清晰的父子关系示例，详见 [第 12 章](#12-project-聚合示例project-与-projectsetting)。

**跨 Aggregate 协作：EventStore**

```
Projects::CreateService
    └── publish Projects::ProjectCreatedEvent
            ├── → Onboarding workers 订阅
            ├── → Analytics workers 订阅
            └── → 其他 context 的 Sidekiq worker 订阅
```

---

### 4.4 Domain Service — 领域服务

**GitLab 实现**：`app/services/<bounded_context>/` 下的 Service 类，封装单个用例（use case）的业务逻辑。

**Project 相关 Domain Service**：

```
app/services/projects/
├── create_service.rb                   # 创建项目
├── update_service.rb                   # 更新项目
├── destroy_service.rb                  # 删除项目
├── archive_service.rb                  # 归档
├── unarchive_service.rb                # 取消归档
├── transfer_service.rb                 # 转移到其他 namespace
├── fork_service.rb                     # Fork
├── import_service.rb                   # 导入
├── restore_service.rb                  # 恢复
├── mark_for_deletion_service.rb        # 标记待删除
├── cleanup_service.rb                  # 清理
├── update_statistics_service.rb        # 更新统计
├── protect_default_branch_service.rb   # 保护默认分支
├── git_deduplication_service.rb        # Git 去重
├── update_repository_storage_service.rb  # 更新仓库存储
├── schedule_bulk_repository_shard_moves_service.rb
├── after_rename_service.rb             # 重命名后处理
├── base_move_relations_service.rb      # 移动关联数据基类
├── move_project_members_service.rb     # 移动成员
├── move_forks_service.rb               # 移动 forks
├── move_access_service.rb              # 移动访问权限
├── ... (约 60+ 个 service 文件)
└── 子目录/
    ├── alert_management/
    ├── auto_devops/
    ├── branch_rules/
    ├── container_repository/
    ├── deploy_tokens/
    ├── forks/
    ├── group_links/
    ├── hashed_storage/
    ├── import_export/
    ├── lfs_pointers/
    ├── operations/
    └── prometheus/
```

**命名规范**（Ubiquitous Language）：

```ruby
# Good — 使用产品语言
Projects::CreateService
Projects::TransferService
Projects::ArchiveService

# Bad — CRUD 术语泄漏（官方文档反例）
EpicIssues::CreateService   # 应为 Epic::AddExistingIssueService
```

**Service 职责**：

1. 接收参数，执行业务规则；
2. 协调多个 Entity 的创建/更新（在一个 transaction 内）；
3. 发布 Domain Event；
4. 返回 `ServiceResponse` 结果。

**示例流程（CreateService → Event）**：

```
Projects::CreateService#execute
    ├── 创建 Project AR 记录
    ├── 创建关联 ProjectSetting、ProjectFeature 等
    ├── 初始化 Repository
    └── publish Projects::ProjectCreatedEvent
            └── Gitlab::EventStore.publish(event)
```

---

### 4.5 Repository — 仓储（Query Object 替代）

**GitLab 实现**：**基本没有 classic Repository 模式**。数据访问通过：

| 替代方案 | 路径 | Project 示例 |
|----------|------|--------------|
| ActiveRecord 直接查询 | Model 类方法 / scope | `Project.find(id)`、`Project.active` |
| Finder（Query Object） | `app/finders/` | `ProjectsFinder`、`GroupProjectsFinder` |
| 专用 Provider | `lib/gitlab/` | `Gitlab::CycleAnalytics::GroupProjectsProvider` |

**Project 相关 Finder（约 30+ 个）**：

```
app/finders/
├── projects_finder.rb                          # 主 Finder：按多种条件过滤 Project
├── contributed_projects_finder.rb
├── fork_projects_finder.rb
├── group_projects_finder.rb
├── personal_projects_finder.rb
├── starred_projects_finder.rb
├── users_star_projects_finder.rb
├── merge_request_target_project_finder.rb
├── autocomplete/project_finder.rb
└── projects/
    ├── branch_rules_finder.rb
    ├── daily_statistics_finder.rb
    ├── export_job_finder.rb
    ├── group_group_links_finder.rb
    ├── groups_finder.rb
    ├── project_group_links_finder.rb
    ├── topics_finder.rb
    ├── members/
    │   ├── effective_access_level_finder.rb
    │   └── effective_access_level_per_user_finder.rb
    └── ml/
        ├── candidate_finder.rb
        ├── experiment_finder.rb
        ├── model_finder.rb
        └── model_version_finder.rb
```

**Finder vs Repository 的区别**：

- **Repository**（经典 DDD）：封装 aggregate 的持久化，提供 `find`、`save`、`delete` 等语义化接口；
- **Finder**（GitLab）：封装复杂查询逻辑，返回 `ActiveRecord::Relation`，**只读**为主。

GitLab 选择 Finder + ActiveRecord 而非 Repository，是因为 Rails 生态中 ActiveRecord 已经提供了足够的 persistence abstraction，再加一层 Repository 会被视为 over-engineering。

---

### 4.6 Domain Event — 领域事件

**GitLab 实现**：`app/events/<namespace>/` + `Gitlab::EventStore` 发布-订阅系统。

**Project 相关 Domain Event**：

```
app/events/projects/
├── project_created_event.rb
├── project_deleted_event.rb
├── project_archived_event.rb
├── project_transfered_event.rb
├── project_path_changed_event.rb
├── project_visibility_changed_event.rb
├── project_features_changed_event.rb
└── release_published_event.rb

ee/app/events/projects/                         # EE 扩展
├── compliance_framework_changed_event.rb
└── security_attribute_changed_event.rb
```

**Event 基础设施**：

```
lib/gitlab/event_store/
├── event.rb            # 基类 Gitlab::EventStore::Event
├── store.rb            # 发布/订阅
├── subscriber.rb
├── subscription.rb
└── cloud_event.rb
```

**命名规范**：

```
<DomainObject><PastTenseAction>Event

Projects::ProjectCreatedEvent       ✓
Projects::ProjectDeletedEvent       ✓
Projects::AddProjectEvent           ✗ (应为 CreatedEvent)
Project::MergeRequestCreatedEvent   ✗ (scope 不对，MR 不属于 Projects context)
```

**Event Schema 示例**（`Projects::ProjectCreatedEvent`）：

```ruby
module Projects
  class ProjectCreatedEvent < ::Gitlab::EventStore::Event
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
end
```

**发布方（Producer）**：

```
app/services/projects/create_service.rb
    └── Gitlab::EventStore.publish(Projects::ProjectCreatedEvent.new(...))
```

**订阅方（Consumer）**：

各 Bounded Context 通过 Sidekiq worker 订阅 event，在 `config/event_store_subscriptions.yml` 或 initializer 中注册。订阅方与发布方解耦，符合 Open-Closed Principle。

**设计原则**（来自 `doc/development/event_store.md`）：

| 原则 | 好 | 坏 |
|------|----|----|
| Semantic | `ProjectCreatedEvent` | `NotifyAdminEvent` |
| Specific | `ProjectVisibilityChangedEvent` | `ProjectChangedEvent` |
| Scoped | `Projects::ProjectCreatedEvent` | `Namespace::ProjectCreatedEvent` |

---

### 4.7 Factory / Builder — 工厂与构建器

**GitLab 实现**：按场景分散，没有统一的 Factory 基类。

**Project 相关的 Builder / Factory**：

| 类型 | 路径 | 用途 |
|------|------|------|
| Import ObjectBuilder | `lib/gitlab/import_export/project/object_builder.rb` | 导入时 find-or-create 关联对象 |
| Hook Data Builder | `lib/gitlab/hook_data/project_builder.rb` | 构建 webhook payload |
| Hook Member Builder | `lib/gitlab/hook_data/project_member_builder.rb` | 构建成员变更 webhook payload |
| Data Builder | `lib/gitlab/data_builder/repository.rb` | 构建系统事件 payload |
| Import Representation | `lib/gitlab/github_import/representation/` | 外部数据 → 内部对象的 DTO |
| Project Transfer | `lib/gitlab/project_transfer.rb` | 项目转移逻辑协调 |
| Legacy Creator | `lib/gitlab/legacy_github_import/project_creator.rb` | GitHub 导入创建 Project |

**Import ObjectBuilder 示例**：

```
lib/gitlab/import_export/
├── base/object_builder.rb              # 基类
├── project/object_builder.rb           # Project 导入时的 find-or-create
└── group/object_builder.rb

ee/lib/ee/gitlab/import_export/project/object_builder.rb   # EE 扩展
```

职责：给定 class + attributes，在 group/project 层级 find 或 create 对象（如 Label、Milestone）。

**Hook Data Builder 示例**：

```
lib/gitlab/hook_data/
├── base_builder.rb
├── project_builder.rb                  # 构建 project_rename 等 webhook payload
└── project_member_builder.rb
```

职责：将 `Project` Entity 转换为 webhook 消费的 Hash 结构（读模型 / DTO）。

**Data Builder 示例**：

```
lib/gitlab/data_builder/
├── repository.rb                       # 构建 push 等系统事件的 payload
├── push.rb
├── pipeline.rb
└── ...
```

**与 DDD Factory 的区别**：

- **Factory**（经典 DDD）：创建 complex aggregate，保证 invariant；
- **GitLab Builder**：更多是 **DTO 转换**（Entity → Hash/JSON）或 **导入场景的 find-or-create**，而非 aggregate 工厂。

Project 的创建 invariant 保障主要在 `Projects::CreateService` 中，而非 Factory 类。

---

## 5. 支撑层（非 Domain Object，但密切相关）

以下层不参与领域建模，但围绕 Domain Object 运作：

| 层 | 路径 | Project 示例 | 角色 |
|----|------|--------------|------|
| **Policy** | `app/policies/` | `project_policy.rb`、`projects/` | 授权决策 |
| **Presenter** | `app/presenters/` | `project_presenter.rb` | 视图层展示逻辑 |
| **Serializer** | `app/serializers/` | project 相关 serializer | JSON 响应 |
| **API Entity** | `lib/api/entities/` | `project.rb`、`project_detail.rb` | REST API DTO（**不是** DDD Entity） |
| **GraphQL Type** | `app/graphql/types/` | `project_type.rb` | GraphQL 响应 |
| **Worker** | `app/workers/` | project 相关 async job | 异步副作用 |
| **Controller** | `app/controllers/projects/` | 按 scope 组织（非 bounded context） | HTTP 入口 |

---

## 6. 架构关系图

```
┌─────────────────────────────────────────────────────────────────┐
│                    Application Layer (无 BC 强制)                  │
│  app/controllers/projects/   lib/api/   app/graphql/            │
└───────────────────────────────┬─────────────────────────────────┘
                                │ 调用
┌───────────────────────────────▼─────────────────────────────────┐
│                      Domain Layer (Bounded Context)                │
│                                                                     │
│  ┌────────────── Projects:: ──────────────────────────────────┐    │
│  │  Entity: Project, ProjectSetting, ProjectFeature, ...      │    │
│  │  Service: CreateService, TransferService, ArchiveService   │    │
│  │  Event:   ProjectCreatedEvent, ProjectDeletedEvent, ...    │    │
│  │  Finder:  ProjectsFinder, GroupProjectsFinder              │    │
│  │  PORO:    Projects::Forks::Details                          │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ┌────────────── Repositories:: ──────────────────────────────┐    │
│  │  lib/gitlab/git/commit.rb, blob.rb, branch.rb              │    │
│  │  (Git 领域对象，通过 project.repository 访问)                │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ┌────────────── Ci:: / MergeRequests:: / WorkItems:: / ... ──┐    │
│  │  (各自独立，通过 project_id 关联 Project)                    │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  EventStore: Gitlab::EventStore.publish / subscribe               │
└───────────────────────────────┬─────────────────────────────────┘
                                │ 持久化
┌───────────────────────────────▼─────────────────────────────────┐
│  PostgreSQL (db/docs/projects.yml, project_settings.yml, ...)   │
│  Gitaly (Git 对象存储)                                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. Project 生命周期中的 DDD 协作示例

以 **创建 Project** 为例，各 DDD 概念如何协作：

```
1. [Application Layer]
   POST /projects → ProjectsController#create

2. [Domain Service]
   Projects::CreateService#execute
   ├── 校验参数、权限
   ├── 创建 Project (Entity)
   ├── 创建 ProjectSetting, ProjectFeature 等 (子 Entity)
   ├── 初始化 Repository (Repositories:: context)
   └── publish Projects::ProjectCreatedEvent (Domain Event)

3. [Domain Event → 异步订阅]
   Gitlab::EventStore.publish(event)
   ├── Namespaces::Onboarding::Worker 订阅 → 更新 onboarding 状态
   ├── Analytics::Worker 订阅 → 记录 metrics
   └── ... 其他 context 各自响应

4. [Factory/Builder → 后续场景]
   ├── Webhook 触发时: Gitlab::HookData::ProjectBuilder 构建 payload
   └── 导入场景: Gitlab::ImportExport::Project::ObjectBuilder find-or-create 关联对象

5. [Finder → 查询场景]
   ProjectsFinder.new(current_user, params).execute → 返回 Project 列表
```

---

## 8. 关键参考路径速查

| 类别 | 路径 |
|------|------|
| Bounded Context 注册 | `config/bounded_contexts.yml` |
| 设计指南 | `doc/development/software_design.md` |
| EventStore 指南 | `doc/development/event_store.md` |
| FixedItemsModel 指南 | `doc/development/fixed_items_model.md` |
| 抽象复用指南 | `doc/development/reusing_abstractions.md` |
| Project Entity | `app/models/project.rb` |
| Project Services | `app/services/projects/` |
| Project Events | `app/events/projects/` |
| Project Finders | `app/finders/projects_finder.rb`、`app/finders/projects/` |
| Project Builders | `lib/gitlab/hook_data/project_builder.rb` |
| Import Factory | `lib/gitlab/import_export/project/object_builder.rb` |
| EventStore 基础设施 | `lib/gitlab/event_store/` |
| Schema 文档 | `db/docs/projects.yml` |

---

## 9. 与 Textbook DDD 的主要差异

| Textbook DDD | GitLab 实际 |
|--------------|-------------|
| 独立的 `domain/` 层 | 分散在 `app/models/`、`app/services/`、`lib/gitlab/` |
| 显式 Aggregate Root 类 | 隐式，通过 Entity 关联 + Service 协调 |
| Repository 接口 | ActiveRecord + Finder |
| ValueObject 基类 | PORO / Enum / FixedItemsModel，无统一基类 |
| Domain Event 框架 | 自研 `Gitlab::EventStore`（Sidekiq 之上） |
| Factory 创建 Aggregate | Service 创建 + Builder 做 DTO 转换 |
| Ubiquitous Language | 强制（RuboCop + 代码审查） |
| Bounded Context 隔离 | 命名空间 + EventStore，仍在同一 monolith |

---

## 10. 阅读建议

1. **从 Bounded Context 入手**：先理解 `config/bounded_contexts.yml` 中 `Projects::` 的边界，再看 Project 相关代码。
2. **跟踪一个用例**：从 `Projects::CreateService` 开始，跟踪 Entity 创建 → Event 发布 → Worker 订阅的完整链路。
3. **区分 Entity 与 DTO**：`lib/api/entities/project.rb` 是 API 响应 DTO，不是 domain entity；`app/models/project.rb` 才是。
4. **注意 God Object 治理**：阅读 `doc/development/software_design.md#taming-omniscient-classes`，理解为何新代码不应继续膨胀 `Project` 类。
5. **对比 Work Items**：`app/models/work_items/` 是较新的、更清晰的 aggregate 设计，可作为与 Project 的对比阅读。
6. **Project 的 enum 与 VO**：阅读 [第 11 章](#11-project-相关-enum-与-value-object-专章)，理解 `Gitlab::VisibilityLevel` 与 `Featurable` 常量模式。
7. **Project 聚合边界**：阅读 [第 12 章](#12-project-聚合示例project-与-projectsetting)，理解 `ProjectSetting` 如何作为聚合内实体挂载在 `Project` 上。

---

## 11. Project 相关 Enum 与 Value Object 专章

GitLab **没有**统一的 `ValueObject` 基类。Project 领域的「enum」也不集中在 `app/enums/`（CE 中该目录几乎为空），而是分散在 **模块常量、Rails enum、GraphQL Enum、State machine** 四种形式中。

### 11.1 四种实现形式概览

| 实现方式 | 典型路径 | Value Object 特征 |
|----------|----------|-------------------|
| **模块常量** | `lib/gitlab/visibility_level.rb`、`app/models/concerns/featurable.rb` | 闭集、按值比较、封装领域行为 |
| **Rails `enum`** | `project.rb` 及关联 model 的 enum 列 | 闭集、持久化为整数、生成谓词方法 |
| **GraphQL Enum** | `app/graphql/types/*_enum.rb` | 对外暴露同一套闭集取值 |
| **State machine 状态** | `project_import_state.rb` 等 | 有限状态 + 转换规则 |

### 11.2 项目可见性：Visibility Level

**不是** `Project` 上的 Rails `enum`，而是 **整数列 + 模块常量**。

```
lib/gitlab/visibility_level.rb              # Gitlab::VisibilityLevel
app/models/project.rb                       # include Gitlab::VisibilityLevel
app/graphql/types/visibility_levels_enum.rb
```

| 整数值 | 常量 | 字符串 |
|--------|------|--------|
| 0 | `PRIVATE` | `private` |
| 10 | `INTERNAL` | `internal` |
| 20 | `PUBLIC` | `public` |

**如何体现 Value Object：**

- **无独立 ID**：`projects.visibility_level` 只是整数，语义由 `Gitlab::VisibilityLevel` 定义。
- **闭集**：仅三种合法值；`valid_level?`、`allowed_for?` 封装校验。
- **领域行为**：`private?` / `internal?` / `public?`、`level_name`、`closest_allowed_level`。
- **Ubiquitous Language**：与产品中的 Private / Internal / Public 一致。

这是 GitLab 最典型的 Value Object 模式：**值 + 规则 + 行为挂在 module 上，Entity 只存整数**。

### 11.3 功能开关级别：Feature Access Level

**同样不是 Rails enum**，而是 `ProjectFeature` 上多个 `*_access_level` 整数列 + `Featurable` concern 常量。

```
app/models/concerns/featurable.rb
app/models/project_feature.rb
app/graphql/types/project_feature_access_level_enum.rb
```

| 整数值 | 常量 | 含义 |
|--------|------|------|
| 0 | `DISABLED` | 对所有人关闭 |
| 10 | `PRIVATE` | 仅团队成员可用 |
| 20 | `ENABLED` | 能访问项目的人可用 |
| 30 | `PUBLIC` | 对所有人开放（主要用于 Pages） |

约 20 个 feature 字段复用同一套取值：`issues_access_level`、`merge_requests_access_level`、`repository_access_level`、`pages_access_level`、`container_registry_access_level` 等（完整列表见 `ProjectFeature::FEATURES`）。

**如何体现 Value Object：**

- 同一 **FeatureAccessLevel** 值对象在多个 Entity 属性上复用。
- `PAGES_ACCESS_LEVELS_BY_PROJECT_VISIBILITY` 将 **Visibility Level** 与 **Feature Access Level** 两个值对象组合成业务规则。
- GraphQL 的 `Types::ProjectFeatureAccessLevelEnum` 直接映射 `ProjectFeature::DISABLED` 等常量。

### 11.4 成员角色：Gitlab::Access（Project 权限基础）

```
lib/gitlab/access.rb
```

| 整数值 | 常量 | 角色 |
|--------|------|------|
| 10 | `GUEST` | Guest |
| 20 | `REPORTER` | Reporter |
| 30 | `DEVELOPER` | Developer |
| 40 | `MAINTAINER` | Maintainer |
| 50 | `OWNER` | Owner |

Project 成员（`ProjectMember`）、授权（`ProjectAuthorization`）、Feature 可见性（`ProjectFeature.required_minimum_access_level`）都引用这套值对象，而非各自定义一套。

### 11.5 Project 关联 Model 上的 Rails enum

#### Project 本体

```ruby
# app/models/project.rb
enum :auto_cancel_pending_pipelines, { disabled: 0, enabled: 1 }
```

#### ProjectSetting

```ruby
# app/models/project_setting.rb
enum :reviewer_assignment_strategy, { disabled: 0, code_owners: 1 }
# via Projects::SquashOption concern:
enum :squash_option, { never: 0, always: 1, default_on: 2, default_off: 3 }
```

| 字段 | 取值 | 产品语义（squash） |
|------|------|-------------------|
| `reviewer_assignment_strategy` | `disabled`, `code_owners` | — |
| `squash_option` | `never`, `always`, `default_on`, `default_off` | 不允许 / 强制 / 鼓励 / 允许 |

#### ProjectAutoDevops

```ruby
enum :deploy_strategy, { continuous: 0, manual: 1, timed_incremental: 2 }
```

#### ProjectRepository

```ruby
enum :object_format, { sha1: 0, sha256: 1 }
```

Git 对象哈希算法，属于仓库领域的值选择。

#### ProjectCiCdSetting

```ruby
enum :pipeline_variables_minimum_override_role, {
  no_one_allowed: 1, developer: 2, maintainer: 3, owner: 4
}
enum :resource_group_default_process_mode, {
  unordered: 0, oldest_first: 1, newest_first: 2, newest_ready_first: 3
}  # 引用 Ci::ResourceGroup::RESOURCE_GROUP_PROCESS_MODES
```

#### Projects 命名空间下的 enum

```ruby
# app/models/projects/ci_feature_usage.rb
enum :feature, { code_coverage: 1, security_report: 2 }

# app/models/projects/import_export/relation_import_tracker.rb
enum :relation, { issues: 0, merge_requests: 1, ci_pipelines: 2, milestones: 3 }
```

#### EE 扩展

```ruby
# ee/app/models/ee/project_ci_cd_setting.rb
enum :restrict_pipeline_cancellation_role, { developer: 0, maintainer: 1, no_one: 2 }
```

### 11.6 相关但不在 Project Model 上的 enum

| 位置 | 说明 |
|------|------|
| `Users::ProjectCallout#feature_name` | UI 横幅 dismiss 状态，偏 presentation |
| `LfsObjectsProject#repository_type` | `project` / `wiki` / `design` |
| `Types::ProjectSortEnum` | GraphQL 项目列表排序 |
| `Types::NamespaceProjectSortEnum` | GraphQL namespace 下项目排序 |
| `Types::ProjectMemberRelationEnum` | GraphQL 成员关系筛选 |
| `Types::Organizations::GroupsProjectsDisplayEnum` | 组织视图展示模式 |

### 11.7 State Machine 状态（类 enum，强调生命周期）

| Model | 路径 | 状态示例 |
|-------|------|----------|
| `ProjectImportState` | `app/models/project_import_state.rb` | `none` → `scheduled` → `started` → `finished` / `failed` / `canceled` |
| `Projects::ImportExport::RelationImportTracker` | `app/models/projects/import_export/relation_import_tracker.rb` | `created` / `started` / `finished` / `failed` |
| `ProjectExportJob` | `app/models/project_export_job.rb` | `queued` → … |

状态值同样是闭集，但额外封装了 **状态转换规则**（比单纯 enum 更接近状态 Value Object + 领域规则）。

### 11.8 DDD Value Object 特征对照

| DDD 特征 | GitLab 中的体现 | Project 示例 |
|----------|-----------------|--------------|
| 按值相等，无独立身份 | 存为整数，不靠 `id` 区分语义 | `visibility_level = 20` 即 Public |
| 闭集 | 常量 Hash 或 Rails enum | `deploy_strategy` 三选一 |
| 不可变（理想） | 模块常量为 frozen；AR 字段可 update | 改 visibility 是替换整列值 |
| 封装校验与行为 | module / concern 类方法 | `VisibilityLevel.allowed_for?(user, level)` |
| Ubiquitous Language | 命名与产品一致 | `default_on` → UI「Encourage squash」 |
| 与 Entity 分离 | Entity 存整数，语义在 module | `Project#visibility_level` + `Gitlab::VisibilityLevel` |

**两种实现层次：**

```
┌─────────────────────────────────────────────────────────┐
│  Entity: Project / ProjectFeature / ProjectSetting       │
│  （有 id，有生命周期）                                    │
│    ├── visibility_level: Integer  ──→ Gitlab::VisibilityLevel
│    ├── issues_access_level: Integer ──→ Featurable
│    └── auto_cancel_pending_pipelines: enum（VO 内嵌在 AR）
└─────────────────────────────────────────────────────────┘
```

- **Visibility / Feature Access / Access Level**：VO 语义在 **module/concern**，Entity 只存整数 → 最接近 textbook VO。
- **Rails enum 字段**：VO 语义 **内嵌在 ActiveRecord enum** → 简单闭集，行为较少。
- **GraphQL Enum**：**对外 VO 视图**，映射领域常量。

### 11.9 与 Textbook Value Object 的差异

1. **大多不可单独实例化**：没有 `VisibilityLevel.new(:public)`，而是整数 + 模块方法。
2. **可变性**：Entity 上的 enum 字段会随 `update` 改变；严格 immutable VO 在这里是 pragmatic 妥协。
3. **行为分散**：校验在 model validation，转换在 `VisibilityLevel.level_value`，查询在 scope。
4. **`app/enums/` 不是主路径**：Project 领域几乎不用 Sorbet 风格 `*Enum` 类；更常见的是 concern 常量 + Rails enum。

### 11.10 Project 相关 Enum 速查表

| 领域概念 | 实现 | 类型 |
|----------|------|------|
| 项目可见性 | `Gitlab::VisibilityLevel` | 模块常量 VO |
| 功能开关级别 | `Featurable::{DISABLED,PRIVATE,ENABLED,PUBLIC}` | 模块常量 VO |
| 成员角色 | `Gitlab::Access::{GUEST..OWNER}` | 模块常量 VO |
| 自动取消 Pipeline | `Project#auto_cancel_pending_pipelines` | Rails enum |
| Squash 策略 | `ProjectSetting#squash_option` | Rails enum |
| Reviewer 分配策略 | `ProjectSetting#reviewer_assignment_strategy` | Rails enum |
| Auto DevOps 部署策略 | `ProjectAutoDevops#deploy_strategy` | Rails enum |
| Git 对象格式 | `ProjectRepository#object_format` | Rails enum |
| Pipeline 变量覆盖角色 | `ProjectCiCdSetting#pipeline_variables_minimum_override_role` | Rails enum |
| Resource Group 模式 | `ProjectCiCdSetting#resource_group_default_process_mode` | Rails enum |
| 导入关系类型 | `RelationImportTracker#relation` | Rails enum |
| CI 功能使用类型 | `Projects::CiFeatureUsage#feature` | Rails enum |
| Pipeline 取消限制角色 (EE) | `ProjectCiCdSetting#restrict_pipeline_cancellation_role` | Rails enum |
| API 可见性 | `Types::VisibilityLevelsEnum` | GraphQL VO |
| API 功能级别 | `Types::ProjectFeatureAccessLevelEnum` | GraphQL VO |

### 11.11 关键路径

| 类别 | 路径 |
|------|------|
| 可见性 VO | `lib/gitlab/visibility_level.rb` |
| 功能级别 VO | `app/models/concerns/featurable.rb` |
| 成员角色 VO | `lib/gitlab/access.rb` |
| Feature Entity | `app/models/project_feature.rb` |
| Squash enum | `app/models/concerns/projects/squash_option.rb` |
| GraphQL 可见性 | `app/graphql/types/visibility_levels_enum.rb` |
| GraphQL 功能级别 | `app/graphql/types/project_feature_access_level_enum.rb` |

---

## 12. Project 聚合示例：Project 与 ProjectSetting

GitLab **没有**显式声明 `AggregateRoot` 类，但 `Project` + `ProjectSetting` 的组合在代码与 schema 上呈现出清晰的 **聚合（Aggregate）** 特征：`Project` 是聚合根，`ProjectSetting` 是聚合内实体，生命周期与身份都依附于 Project。

> 注意：GitLab 官方文档称 `Project` 为 omniscient class（上帝对象），整个 monolith 里它关联的内容远多于一个 strict DDD aggregate 应包含的范围。本章只讨论 **workspace 设置子域** 中 `ProjectSetting` 与 `Project` 的关系，而非把 Issue、Pipeline 等也纳入同一聚合。

### 12.1 聚合边界（务实视角）

在 `Projects::` Bounded Context 内，可以把 **Project workspace 设置** 理解为一个松散聚合：

```
Project (Aggregate Root — workspace 身份与生命周期)
├── ProjectSetting          ← 项目级配置（本章重点）
├── ProjectFeature          ← 功能开关（issues/wiki/builds 等）
├── ProjectCiCdSetting      ← CI/CD 配置
├── ProjectRepository       ← 仓库元数据（非 Git 对象）
├── ProjectAutoDevops       ← Auto DevOps 配置
└── …（其他 1:1 设置型 Entity）

不在此聚合内（独立 Bounded Context / 独立生命周期）：
├── Issue / MergeRequest / WorkItem
├── Ci::Pipeline
├── Repository (Git 对象，经 Gitaly)
└── Packages / Deployments / …
```

`ProjectSetting` 与 `ProjectFeature`、`ProjectCiCdSetting` 等同属 **「Project 的 1:1 配置实体」** 簇；它们共享相似的挂载模式（`has_one` + `autosave` + nested attributes + delegate）。

### 12.2 数据模型层：身份依附于聚合根

`project_settings` 表的设计直接体现了 **组合（Composition）** 而非独立聚合：

| 设计点 | 实现 | DDD 含义 |
|--------|------|----------|
| 主键 | `project_id` 即 PRIMARY KEY | 子实体 **没有独立 surrogate id**，身份 = 所属 Project |
| 外键 | `project_id REFERENCES projects(id) ON DELETE CASCADE` | 删除 Project 时级联删除 Setting |
| 分片键 | `db/docs/project_settings.yml` → `project_id: projects` | 与 Project 同生命周期、同 sharding 边界 |
| 描述 | `Stores settings per project` | 纯附属配置，不能脱离 Project 存在 |

```
db/docs/project_settings.yml
db/structure.sql → CREATE TABLE project_settings ( project_id bigint NOT NULL, ... )
                   → PRIMARY KEY (project_id)
                   → FK ... ON DELETE CASCADE
```

这是 textbook DDD 中 **聚合内 Entity** 的典型数据库信号：子对象以根的身份作为主键，而非全局唯一 ID。

### 12.3 ActiveRecord 关联层

```ruby
# app/models/project.rb
has_one :project_setting, inverse_of: :project, autosave: true
accepts_nested_attributes_for :project_setting, update_only: true

# app/models/project_setting.rb
belongs_to :project, inverse_of: :project_setting
```

| 机制 | 作用 | 聚合含义 |
|------|------|----------|
| `has_one` / `belongs_to` | 1:1 组合关系 | Setting 从属于 Project |
| `autosave: true` | 保存 Project 时自动持久化关联 Setting | 单一持久化单元（pragmatic） |
| `accepts_nested_attributes_for ..., update_only: true` | 通过 `project_setting_attributes` 批量更新 | **只允许经聚合根修改**（创建后） |
| `inverse_of` | 双向关联一致性 | 对象图完整性 |

**Lazy 初始化（聚合内对象按需构建）**：

```ruby
# app/models/project.rb
def project_setting
  super.presence || build_project_setting
end
```

访问 `project.project_setting` 时，若 DB 中尚无行，则在内存中 `build_project_setting`，首次保存发生在 `CreateService` 或后续 `project.save`/`update` 时。这保证聚合根始终是访问 Setting 的入口。

对比：`ProjectFeature` 在 `after_create` 中强制 `create_or_load_association(:project_feature)` 并 `validates :project_feature, presence: true`；`ProjectSetting` 则更 **lazy**，允许创建后延迟落库。

### 12.4 聚合根 Facade：Delegate 到 ProjectSetting

`Project` 将大量设置 **委托** 给 `project_setting`，对外呈现为聚合根 API：

```ruby
# app/models/project.rb（节选）
with_options to: :project_setting do
  delegate :squash_option, :squash_option=
  delegate :mr_default_target_self, :mr_default_target_self=
  delegate :merge_commit_template, :merge_commit_template=
  delegate :runner_registration_enabled, :runner_registration_enabled=
  # ... 数十个 delegate
end
```

**DDD 解读**：

- 外部调用方（Controller、Service、View）通常调用 `project.squash_option`，而非 `project.project_setting.squash_option`。
- 聚合根充当 **Facade**，隐藏内部结构，符合「通过 Aggregate Root 访问聚合内对象」的原则。
- 部分 CI 相关设置则委托给 `ci_cd_settings`（另一个 1:1 子实体），说明 workspace 聚合实际上是一个 **cluster**，而非单一 `ProjectSetting` 表。

### 12.5 生命周期：创建

```
Projects::CreateService#execute
    ├── 创建 Project 记录（Entity 落库）
    ├── after_create_actions
    │     ├── create_project_settings
    │     │     ├── Gitlab::Pages.add_unique_domain_to(project)  # 可选
    │     │     └── @project.project_setting.save if changed?    # 首次持久化 Setting
    │     ├── publish Projects::ProjectCreatedEvent
    │     └── ...
    └── ...
```

```ruby
# app/services/projects/create_service.rb
def create_project_settings
  Gitlab::Pages.add_unique_domain_to(project) if Gitlab::CurrentSettings.pages_unique_domain_default_enabled
  @project.project_setting.save if @project.project_setting.changed?
end
```

**聚合一致性**：

- Project 必须先存在（有 `id`），Setting 才能以 `project_id` 为主键落库。
- 创建用例由 `Projects::CreateService` 编排，而非单独 `ProjectSetting.create`。
- 创建完成后发布 `Projects::ProjectCreatedEvent`，其他 context 通过 event 响应，而非在 CreateService 里直接修改它们的数据。

### 12.6 生命周期：更新

**标准路径：经聚合根 + Domain Service**

```ruby
# app/services/projects/update_service.rb
def update_project!
  project.update!(params.except(*non_assignable_project_params))
end
```

调用方传入 nested attributes：

```ruby
Projects::UpdateService.new(project, current_user,
  project_setting_attributes: { squash_option: squash_option }
).execute
```

Web 表单同样经聚合根：

```
project[project_setting_attributes][squash_option]
project[project_setting_attributes][show_default_award_emojis]
```

**子 Service 也路由到 UpdateService**（不直接改 Setting 表）：

```ruby
# app/services/projects/branch_rules/squash_options/update_service.rb
Projects::UpdateService.new(project, current_user,
  project_setting_attributes: { squash_option: squash_option }
).execute
```

**UpdateService 内的聚合级校验**（根协调子对象规则）：

```ruby
# 例：修改 pages 相关 setting 前，由 Service 调用 Gitlab::Pages.add_unique_domain_to(project)
def add_pages_unique_domain
  return unless params.dig(:project_setting_attributes, :pages_unique_domain_enabled)
  Gitlab::Pages.add_unique_domain_to(project)
end
```

**ProjectSetting 自身校验**（实体不变量，引用聚合根常量）：

```ruby
# app/models/project_setting.rb
validates :merge_commit_template, length: { maximum: Project::MAX_COMMIT_TEMPLATE_LENGTH }
validates :target_platforms, inclusion: { in: ALLOWED_TARGET_PLATFORMS }
validate :validates_mr_default_target_self
```

子实体校验依赖 `Project` 类常量，表明两者在同一 **一致性边界** 内。

**级联设置（Cascading）**：`ProjectSetting` include `CascadingProjectSettingAttribute`，部分属性可从 Group / Instance 继承；读取时合并祖先值，写入时校验是否可覆盖。这是 aggregate 内实体与 **外部 policy**（namespace/instance）之间的规则，仍由 `ProjectSetting` 模型封装。

### 12.7 生命周期：删除

```
Projects::DestroyService
    └── project.destroy!
            └── DB CASCADE → project_settings 行随 projects 删除
```

- `project_settings` 无 `dependent:` 声明在 `has_one` 上，因为 **数据库 FK CASCADE** 已保证删除一致性。
- 子实体不能独立于 Project 存在，符合组合生命周期。

### 12.8 与聚合内兄弟实体对比

| 子实体 | 关联 | 创建时机 | 聚合特征 |
|--------|------|----------|----------|
| `ProjectSetting` | `has_one`, `autosave` | CreateService lazy save | PK = project_id |
| `ProjectFeature` | `has_one` | `after_create` 强制创建 | `validates presence` |
| `ProjectCiCdSetting` | `has_one`, `autosave`, `dependent: :destroy` | `after_create` + UpdateService backfill | nested attributes |
| `ProjectAutoDevops` | `has_one` | 按需 | nested attributes |

三者共同构成 **Project workspace 配置聚合簇**；GitLab 用相同模式（nested attributes + delegate + Service）管理它们，但未在代码中显式命名 aggregate。

### 12.9 偏离 Strict Aggregate 之处

GitLab 的实现是 **pragmatic DDD**，并非严格聚合 enforcement：

| 现象 | 位置 | 说明 |
|------|------|------|
| 直接查询 `ProjectSetting` | `Projects::RecordTargetPlatformsService` | `ProjectSetting.find_or_initialize_by(project: project)` |
| Worker 绕过聚合根 | `Pages::ResetPagesDefaultDomainRedirectWorker` | `ProjectSetting.find_by_project_id(...)` |
| 无 Repository 封装 | 全局 | 任何代码均可 `ProjectSetting.where(...)`，无编译期边界 |
| Project 关联过多 | `project.rb` | Issue、Pipeline 等与 Setting 同属一个 AR 类，但 **不是** 同一 aggregate |
| Lazy vs Eager 创建 | Setting lazy / Feature eager | 历史上曾出现缺失 Setting 的行，需 background migration 修复 |

因此：**概念上** 可把 `ProjectSetting` 视为 `Project` 聚合的一部分；**工程上** 依赖约定（Service + nested attributes + delegate）而非硬隔离。

### 12.10 协作关系图

```
                    ┌─────────────────────────────────────┐
                    │     Projects::CreateService         │
                    │     Projects::UpdateService         │
                    │     Projects::DestroyService        │
                    └──────────────┬──────────────────────┘
                                   │ 编排
                    ┌──────────────▼──────────────────────┐
                    │  Project (Aggregate Root)           │
                    │  app/models/project.rb              │
                    │  • has_one :project_setting          │
                    │  • accepts_nested_attributes        │
                    │  • delegate squash_option, ...        │
                    └──────────────┬──────────────────────┘
                                   │ 1:1 组合
                    ┌──────────────▼──────────────────────┐
                    │  ProjectSetting (聚合内 Entity)      │
                    │  app/models/project_setting.rb      │
                    │  PK = project_id                    │
                    │  • squash_option (enum)             │
                    │  • merge_commit_template            │
                    │  • pages_unique_domain              │
                    │  • CascadingProjectSettingAttribute │
                    └─────────────────────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │  project_settings (PostgreSQL)      │
                    │  ON DELETE CASCADE                  │
                    └─────────────────────────────────────┘

  对外 API / UI ──→ project.update(project_setting_attributes: {...})
                 ──→ project.squash_option  (delegate，不暴露内部结构)
```

### 12.11 关键路径速查

| 类别 | 路径 |
|------|------|
| 聚合根 | `app/models/project.rb` |
| 聚合内 Entity | `app/models/project_setting.rb` |
| Squash 设置 concern | `app/models/concerns/projects/squash_option.rb` |
| 级联属性 concern | `app/models/concerns/cascading_project_setting_attribute.rb` |
| 创建编排 | `app/services/projects/create_service.rb` → `#create_project_settings` |
| 更新编排 | `app/services/projects/update_service.rb` → `#update_project!` |
| Squash 更新（经根） | `app/services/projects/branch_rules/squash_options/update_service.rb` |
| Schema | `db/docs/project_settings.yml`、`db/structure.sql` |
| 表说明 | `Stores settings per project` |
