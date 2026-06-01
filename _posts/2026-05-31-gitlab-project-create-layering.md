---
title: "GitLab Project 创建：代码分层与架构原则"
date: 2026-05-31 19:00:00 +0800
categories: [GitLab, Projects, Architecture, DDD]
tags: [project, namespace, use-case, service, adapter, bounded-context, event-store, gitaly]
description: >-
  以 Project 创建为完整用例，分析 GitLab 从 REST/Web 入口到 Model、Namespace、Gitaly 仓库、Worker、EventStore 的分层组织，以及与 Issue 创建的模式差异。
---

> 本文基于 GitLab 源码（`gitlab-org/gitlab`）与官方设计文档整理。  
> 分析日期：2026-05-31  
> 对照：[Issue 创建分层](/posts/gitlab-issue-create-layering/) · [Release 分层](/posts/gitlab-release/)

## 目录

1. [Project 创建是什么](#1-project-创建是什么)
2. [代码架构总览](#2-代码架构总览)
3. [Projects 限界上下文](#3-projects-限界上下文)
4. [端到端调用链](#4-端到端调用链)
5. [各层职责详解](#5-各层职责详解)
6. [跨上下文协作](#6-跨上下文协作)
7. [符合的架构原则](#7-符合的架构原则)
8. [与 Issue / Release 创建对比](#8-与-issue--release-创建对比)
9. [关键路径速查](#9-关键路径速查)
10. [阅读建议](#10-阅读建议)

---

## 1. Project 创建是什么

**Project 创建** = 在某个 Namespace（用户 personal 或 Group）下新建一个 **工作空间**，包括：

- PostgreSQL 中的 `projects` 记录
- 关联的 `Namespaces::ProjectNamespace`
- Gitaly 上的 **空 Git 仓库**（非 import 场景）
- 默认 labels、integrations、权限、wiki、可选 README/SAST 初始 commit 等

典型入口：

| 入口 | 路径 |
|------|------|
| Web UI | `POST /projects` → `ProjectsController#create` |
| REST API | `POST /projects` → `lib/api/projects.rb` |
| 从模板创建 | 同上，带 `template_name` → 委托 `CreateFromTemplateService` |
| Import | GitHub/Bitbucket 等 `*ProjectCreator` → 同样 `Projects::CreateService` |

**注意**：CE 中 Project 创建 **没有** 独立 GraphQL mutation，主要走 REST 与 Web；Import 路径通过 ACL（ProjectCreator）再调 Service。

所有路径最终汇聚 **`Projects::CreateService#execute`**。

---

## 2. 代码架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│  Primary Adapters（入站）                                         │
│  lib/api/projects.rb · app/controllers/projects_controller.rb     │
│  lib/gitlab/*_import/project_creator.rb（Import ACL）            │
└────────────────────────────┬────────────────────────────────────┘
                             │ params、鉴权、license 过滤、序列化
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Use Case（Projects BC）                                          │
│  Projects::CreateService                                          │
│    ├─ CreateFromTemplateService（子用例：模板）                    │
│    ├─ save_project_and_import_data（transaction）               │
│    └─ after_create_actions（wiki、权限、webhook、Worker…）         │
└────────────────────────────┬────────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
   app/models/project.rb  Repositories BC    Security / Files
   Entity + 校验           create_repository   README / SAST commit
         │                 → Gitaly              │
         ▼                   ▼                   ▼
   PostgreSQL            Git 仓库            Sidekiq Worker
   ProjectNamespace      (Secondary Adapter)  PostCreationWorker
   EventStore            Import schedule
   System Hook
```

与 Issue 不同，Project 创建 **没有** 单独的 BuildService / IssuableBaseService 模板，逻辑集中在单个 `CreateService` 内（历史较长的 Service 风格）。

---

## 3. Projects 限界上下文

`config/bounded_contexts.yml`：

```yaml
Projects:
  description: Managing projects as workspaces and their lifecycle.
               Feature specific behavior must not go here.
  feature_categories:
    - groups_and_projects
```

| 路径 | 职责 |
|------|------|
| `app/models/project.rb` | 聚合根（上帝对象，4000+ 行；**新行为应进 dedicated class**） |
| `app/models/namespaces/project_namespace.rb` | Project 专属 Namespace（与 Project 同步） |
| `app/services/projects/` | Project 生命周期用例（Create / Update / Fork …） |
| `app/events/projects/` | `ProjectCreatedEvent` 等 |

**Repositories** 是相邻 BC：`Project#create_repository` → `repository.create_repository` → Gitaly，Git 细节不进 `Projects::CreateService` 的 wire 层。

---

## 4. 端到端调用链

以 Web 创建空白 Project 为例：

```
POST /projects
    │
    ├─ ProjectsController#create
    │     project_params → Projects::CreateService.new(current_user, params).execute
    │
    └─ Projects::CreateService#execute
          ├─ create_from_template? → CreateFromTemplateService（若带模板）
          ├─ Project.new + assign_attributes + build_ci_cd_settings
          ├─ 可见性 / namespace / 个人项目限额校验
          ├─ validate_create_permissions (:create_projects)
          ├─ save_project_and_import_data
          │     transaction {
          │       Namespaces::ProjectNamespace.create_from_project!
          │       Integration.create_from_default_integrations
          │       project.create_labels
          │       project.create_repository  → Gitaly
          │     }
          └─ after_create_actions（若 persisted）
                ├─ create_wiki / project_setting
                ├─ setup_authorizations（ProjectAuthorization 同步）
                ├─ event_service.create_project
                ├─ execute_hooks（system hook）
                ├─ PostCreationWorker.perform_async
                ├─ Files::CreateService（可选 README）
                ├─ Security::CiConfiguration::*（可选 SAST）
                └─ publish_event → ProjectCreatedEvent
```

REST API（`POST /projects`）同样调用 `CreateService`，额外做 `translate_params_for_compatibility`、`filter_attributes_using_license!` 等 Adapter 逻辑。

---

## 5. 各层职责详解

### 5.1 Primary Adapter — REST API

```ruby
# lib/api/projects.rb
post do
  attrs = declared_params(include_missing: false)
  attrs = translate_params_for_compatibility(attrs)
  attrs = add_import_params(attrs)
  filter_attributes_using_license!(attrs)

  project = ::Projects::CreateService.new(current_user, attrs).execute

  if project.saved?
    present_project project, with: Entities::Project
  else
    render_validation_error!(project)
  end
end
```

Adapter：**HTTP 参数、license 特性门控、present JSON**。不含 transaction 与 Gitaly 调用。

### 5.2 Primary Adapter — Web Controller

```ruby
# app/controllers/projects_controller.rb
def create
  @project = ::Projects::CreateService.new(
    current_user,
    project_params(attributes: project_params_create_attributes)
  ).execute

  @project.saved? ? redirect_to(project_path(@project)) : render('new')
end
```

Controller 只做表单参数与 redirect；**不** `Project.create`。

### 5.3 Import ACL — ProjectCreator

外部格式 → GitLab 领域参数，再调同一 Service：

```ruby
# lib/gitlab/legacy_github_import/project_creator.rb
attrs = { name:, path:, namespace_id:, import_type:, import_url:, ... }
::Projects::CreateService.new(current_user, attrs).execute
```

**防腐层（ACL）** 在 `lib/gitlab/*_import/`，不把 GitHub JSON 解析塞进 `CreateService`。

### 5.4 Use Case — `Projects::CreateService`

核心编排（节选）：

```ruby
# app/services/projects/create_service.rb
def execute
  if create_from_template?
    return ::Projects::CreateFromTemplateService.new(current_user, params).execute
  end

  @project = Project.new.tap do |p|
    p.build_ci_cd_settings
    p.assign_attributes(params.merge(creator: current_user))
  end

  # 可见性、namespace、限额、权限…
  validate_create_permissions
  validate_import_permissions
  return @project if @project.errors.any?

  save_project_and_import_data

  Gitlab::ApplicationContext.with_context(project: @project) do
    after_create_actions if @project.persisted?
    import_schedule
  end

  @project
end
```

| 阶段 | 职责 |
|------|------|
| **参数预处理** | `initialize` 中 delete 专用键（`skip_wiki`、`import_data`、`initialize_with_readme`…） |
| **子用例路由** | 模板 → `CreateFromTemplateService` |
| **构建 Entity** | `Project.new` + `assign_attributes`（无独立 BuildService） |
| **权限** | `:create_projects`、`:import_projects` |
| **持久化** | `save_project_and_import_data`（transaction） |
| **副作用** | `after_create_actions` |
| **返回值** | **`Project` 对象**（非 `ServiceResponse`，见 §8） |

### 5.5 Transaction — `save_project_and_import_data`

```ruby
ApplicationRecord.transaction do
  Namespaces::ProjectNamespace.create_from_project!(@project) if @project.valid?

  if @project.saved?
    Integration.create_from_default_integrations(@project, :project_id)
    @project.create_labels unless @project.gitlab_project_import?
    @project.create_repository(default_branch:, object_format:) unless @project.import?
  end
end
```

**顺序要点**：

1. 先建 **ProjectNamespace**（避免 Rails callback 多次触发，见 issue #421050 注释）
2. 默认 **Integration**、**Labels**
3. 非 import 时 **`create_repository`** 调 Gitaly

### 5.6 Model — `Project` 与 `ProjectNamespace`

**不变量与校验在 Model**：

```ruby
# app/models/project.rb
validate :check_personal_projects_limit, on: :create

def check_personal_projects_limit
  return if creator.can_create_project? || namespace.kind == 'group'
  self.errors.add(:limit_reached, ...)
end

def create_repository(force: false, default_branch: nil, object_format: nil)
  repository.create_repository(default_branch, object_format: object_format)
  repository.after_create
rescue StandardError => e
  errors.add(:base, _('Failed to create repository'))
  false
end
```

Service 调 Model 方法；**Gitaly RPC** 在 `Gitlab::Git::Repository`（Client 封装层），见 [Release §5.6 Client/Service](/posts/gitlab-release/#56-client-与-service-的分工)。

**ProjectNamespace** 与 Project 属性同步（name、path、visibility…），体现 **Namespace 作为 Project 的容器 facet**。

### 5.7 创建后 — `after_create_actions`

```ruby
def after_create_actions
  @project.create_wiki unless skip_wiki?
  @project.track_project_repository
  create_project_settings
  event_service.create_project(@project, current_user)
  execute_hooks                                    # system hook
  setup_authorizations                             # ProjectAuthorization
  Projects::PostCreationWorker.perform_async(@project.id)
  create_readme if @initialize_with_readme         # Files::CreateService
  create_sast_commit if @initialize_with_sast      # Security BC
  publish_event                                    # EventStore
end
```

| 同步（request 内） | 异步 |
|--------------------|------|
| save、Gitaly 建库、权限记录、system hook、EventStore | `PostCreationWorker`（incident tags 等） |
| 可选 README/SAST 初始 commit | Import `import_state.schedule` |
| `AuthorizedProjectUpdate::*Worker` 刷新权限缓存 | |

### 5.8 子用例 — `CreateFromTemplateService`

模板创建 **单独 Service**，不污染主 Create 路径：

```ruby
def execute
  return project unless validate_template!
  GitlabProjectsImportService.new(current_user, params, override_params,
    import_type: 'gitlab_built_in_project_template').execute
end
```

符合 **一用例一 Service**（权限与前置条件不同）。

### 5.9 领域事件

```ruby
event = Projects::ProjectCreatedEvent.new(data: {
  project_id: project.id,
  namespace_id: project.namespace_id,
  root_namespace_id: project.root_namespace.id
})
Gitlab::EventStore.publish(event)
```

JSON Schema 定义在 Event 类；订阅方在其他 BC 解耦。

---

## 6. 跨上下文协作

| 协作 | Service / 调用 | BC |
|------|----------------|-----|
| `project.create_repository` | Model → `Gitlab::Git::Repository` | **Repositories** / Gitaly |
| `Files::CreateService` | 初始 README commit | **Repositories** |
| `Security::CiConfiguration::SastCreateService` | 安全模板 commit | **Security** |
| `GitlabProjectsImportService` | 模板 / import | **Import** |
| `Integration.create_from_default_integrations` | 默认集成 | **Integrations** |
| `AuthorizedProjectUpdate::*Worker` | 权限投影 | **Authorization** |

`Projects` BC 描述 **工作空间生命周期**；Issue/MR/CI 等功能 **不应** 堆进 `Projects::CreateService`（bounded_contexts 注释）。

---

## 7. 符合的架构原则

### 7.1 官方抽象复用规则

| 原则 | Project 创建中的体现 |
|------|---------------------|
| **Use-case 导向** | `Projects::CreateService`，非 Controller 里 `Project.create` |
| **Adapter 薄** | API/Controller 只调 Service + present |
| **权限在 Service** | `validate_create_permissions`、`validate_import_permissions` |
| **Model 守不变量** | `check_personal_projects_limit`、`visibility_level` 校验 |
| **子用例拆分** | `CreateFromTemplateService`、Import 走独立 ImportService |
| **Event 在 Service 发布** | `ProjectCreatedEvent` |
| **Worker 用 perform_async** | `PostCreationWorker` |
| **ACL 与 Core 分离** | `ProjectCreator` 翻译外部数据 |

### 7.2 Clean Architecture / 六边形

| 概念 | Project 创建映射 |
|------|------------------|
| Entity | `Project` + `Namespaces::ProjectNamespace` |
| Use Case | `Projects::CreateService` |
| Primary Adapter | REST、Controller、Import ProjectCreator |
| Secondary Adapter | Gitaly（经 Repository）、System Hook、ActiveRecord |
| 依赖方向 | Adapter → Service → Model → Repository Client |

### 7.3 DDD 与 omniscient 治理

- `Project` 是官方认定的 **上帝对象**；创建逻辑已放在 **`Projects::CreateService`** 而非继续膨胀 Model callback。
- **Facet**：`ProjectNamespace` 承载 namespace 侧行为，减轻 `Project` 职责。
- **Domain Event**：`ProjectCreatedEvent` 供跨 BC 订阅。

### 7.4 历史 pragmatic 差异

| 点 | 说明 |
|----|------|
| **返回 Project 而非 ServiceResponse** | 老 Service 风格；API 用 `project.saved?` / `project.errors` 判断 |
| **initializer `(user, params)`** | 与新版 `container:, current_user:, params:` 并存 |
| **单文件大 Service** | 无 BuildService；transaction + after_create 全在一个类 |

新代码（Issue、Release）更倾向 `ServiceResponse` + 更小拆分；读 Project 时需意识到 **代际差异**。

---

## 8. 与 Issue / Release 创建对比

| 维度 | Project 创建 | Issue 创建 | Release 创建 |
|------|-------------|-----------|--------------|
| Bounded Context | `Projects` | `WorkItems` | `Releases` |
| 入口 | REST + Web（无 CE GraphQL） | REST + GraphQL + Web | REST + GraphQL + Web |
| 返回值 | `Project` | `ServiceResponse` | `ServiceResponse` |
| 构建拆分 | 无 BuildService | `BuildService` + `create` | 内联 `build_release` |
| 共享基类 | 老 `BaseService` | `IssuableBaseService` | `Releases::BaseService` |
| Transaction 内容 | Namespace + 建库 + labels | Issue save + callbacks | Release save |
| 外部 Git | **create_repository**（Gitaly） | 无 | **Tags::CreateService** |
| Event | `ProjectCreatedEvent` | `WorkItemCreatedEvent` | `ReleasePublishedEvent` |
| ACL | Import ProjectCreator | MR discussion → BuildService | `Links::Params` |

Release 创建完整分析见 [Release 创建分层](/posts/gitlab-release-create-layering/)。

**共同点**：Adapter 薄、Service 编排、Model 校验、EventStore、Import/模板走子 Service。

---

## 9. 关键路径速查

| 类别 | 路径 |
|------|------|
| Bounded Context | `config/bounded_contexts.yml` → `Projects:` |
| 聚合根 | `app/models/project.rb` |
| Project Namespace | `app/models/namespaces/project_namespace.rb` |
| **创建用例** | `app/services/projects/create_service.rb` |
| 模板子用例 | `app/services/projects/create_from_template_service.rb` |
| **REST 入口** | `lib/api/projects.rb` |
| **Web 入口** | `app/controllers/projects_controller.rb` |
| Import ACL 示例 | `lib/gitlab/legacy_github_import/project_creator.rb` |
| 建库 | `Project#create_repository` → `lib/gitlab/git/repository.rb` |
| 异步 | `app/workers/projects/post_creation_worker.rb` |
| 领域事件 | `app/events/projects/project_created_event.rb` |
| Spec | `spec/services/projects/create_service_spec.rb` |

---

## 10. 阅读建议

1. **从 Controller/API 跟到 `execute`**：`projects_controller#create` → `CreateService#execute`。
2. **读 `save_project_and_import_data`**：理解 Namespace + 建库 transaction 顺序。
3. **读 `after_create_actions`**：同步副作用 vs `PostCreationWorker`。
4. **对比 Issue 文档**：同一 monolith 里两种 Service 风格（Project 老、Issue 新）。
5. **跑 spec**：`bundle exec rspec spec/services/projects/create_service_spec.rb`。

**延伸阅读**：[Issue 创建分层](/posts/gitlab-issue-create-layering/) · [Project DDD（上帝对象）](/posts/gitlab-ddd-domain-objects/) · [Client/Service](/posts/gitlab-release/#56-client-与-service-的分工)
