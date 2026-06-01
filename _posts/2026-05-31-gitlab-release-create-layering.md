---
title: "GitLab Release 创建：代码分层与架构原则"
date: 2026-05-31 20:00:00 +0800
categories: [GitLab, Releases, Architecture, DDD]
tags: [release, use-case, service, adapter, bounded-context, gitaly, evidence, finder]
description: >-
  以 Release 创建为完整用例，分析 GitLab 从 REST/GraphQL 入口到 Tag、Model、Evidence Worker 的分层组织，以及与 Issue/Project 创建的模式对照。
---

> 本文基于 GitLab 源码（`gitlab-org/gitlab`）与官方设计文档整理。  
> 分析日期：2026-05-31  
> Release 全景（Source PORO、Model/Service/Client 分工）见 [Release 完整文档](/posts/gitlab-release/)  
> 对照：[Issue 创建](/posts/gitlab-issue-create-layering/) · [Project 创建](/posts/gitlab-project-create-layering/)

## 目录

1. [Release 创建是什么](#1-release-创建是什么)
2. [代码架构总览](#2-代码架构总览)
3. [Releases 限界上下文](#3-releases-限界上下文)
4. [端到端调用链](#4-端到端调用链)
5. [各层职责详解](#5-各层职责详解)
6. [跨上下文协作](#6-跨上下文协作)
7. [符合的架构原则](#7-符合的架构原则)
8. [与 Issue / Project 创建对比](#8-与-issue--project-创建对比)
9. [关键路径速查](#9-关键路径速查)
10. [阅读建议](#10-阅读建议)

---

## 1. Release 创建是什么

**Release 创建** = 在某个 **Git tag** 上写入 GitLab 的发布记录（name、description、links、milestones、sha），并触发通知、Webhook、Evidence 收集、Catalog 发布等副作用。

与 Project/Issue 不同，Release **强依赖 Git 层**：

| 层次 | 创建时发生什么 |
|------|----------------|
| Git（Gitaly） | tag 可能已存在，或由 `ref` **新建 tag** |
| PostgreSQL | 新建 `releases` 行，`(project_id, tag)` 唯一 |
| 聚合内 | 可选 nested `release_links`、关联 milestones |

典型入口（**同一用例，多个 Primary Adapter**）：

| 入口 | 路径 |
|------|------|
| REST API | `POST /projects/:id/releases` → `lib/api/releases.rb` |
| GraphQL | `mutation releaseCreate` → `Mutations::Releases::Create` |
| Web（创建 Tag 时附带） | `TagsController#create` → 可选再调 `CreateService` |
| Release CLI / CI job token | 同上 REST，支持 `job_token_policies: :admin_releases` |

所有主路径汇聚 **`Releases::CreateService#execute`**。

---

## 2. 代码架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│  Primary Adapters（入站）                                         │
│  lib/api/releases.rb · GraphQL Mutations::Releases::Create        │
│  app/controllers/projects/tags_controller.rb（Tag+Release 组合）  │
└────────────────────────────┬────────────────────────────────────┘
                             │ 鉴权、参数、Entities::Release 序列化
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Use Case（Releases BC）                                          │
│  Releases::CreateService#execute                                  │
│    ├─ EvidencePipelineFinder（只读，须在 tag 创建前）              │
│    ├─ ensure_tag → Tags::CreateService（Repositories BC）        │
│    └─ create_release：build → save → 副作用                       │
└────────────────────────────┬────────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
   app/models/release.rb  MilestonesFinder    Tags::CreateService
   Entity + 不变量         只读查询            → Git Repository → Gitaly
         │
         ▼
   Notification / Webhook / Audit / CreateEvidenceWorker（异步）
   Ci::Catalog::Resources::ReleaseService（可选）
```

**读路径**（列表 Release）走 `ReleasesFinder`，**不**经过 `CreateService`——典型 CQRS 式读写分离。

---

## 3. Releases 限界上下文

`config/bounded_contexts.yml` → **`Releases:`**（`release_orchestration`、`release_evidence`）

| 路径 | 创建流程中的角色 |
|------|------------------|
| `app/services/releases/create_service.rb` | **创建用例** |
| `app/services/releases/base_service.rb` | 共享参数解析、milestone 查找、hook |
| `app/services/releases/links/params.rb` | Link 参数 ACL（白名单） |
| `app/finders/releases/evidence_pipeline_finder.rb` | 创建前查 CI pipeline（Evidence 用） |
| `app/models/release.rb` | 聚合根：校验、`sha_unchanged`、nested links |
| `app/workers/releases/create_evidence_worker.rb` | 异步 Evidence |

---

## 4. 端到端调用链

以 REST `POST /projects/:id/releases` 为例：

```
POST /projects/:id/releases
    │
    ├─ lib/api/releases.rb
    │     authorize_create_release!
    │     Releases::CreateService.new(project, user, declared_params).execute
    │     present Entities::Release
    │
    └─ Releases::CreateService#execute
          ├─ allowed? (:create_release)
          ├─ can_create_tag? (protected tag)
          ├─ 409 if release already exists for tag
          ├─ 校验 milestone titles/ids
          ├─ EvidencePipelineFinder#execute     ← 必须在 create tag 之前
          ├─ ensure_tag
          │     ├─ existing_tag (repository.find_tag)
          │     └─ Tags::CreateService (若需 ref 建 tag)
          └─ create_release(tag, evidence_pipeline)
                ├─ build_release (nested links, milestones)
                ├─ Ci::Catalog::Resources::ReleaseService（可选）
                ├─ release.save!
                ├─ NotificationService（async）
                ├─ execute_hooks('create')
                ├─ CreateEvidenceWorker.perform_async
                └─ audit(:created)
                → success(tag:, release:)
```

GraphQL `ReleaseCreate` 内部 **同一 Service**，仅参数来自 GraphQL arguments + `assets` input。

---

## 5. 各层职责详解

### 5.1 Primary Adapter — REST API

```ruby
# lib/api/releases.rb
post ':id/releases' do
  authorize_create_release!
  result = ::Releases::CreateService
    .new(user_project, current_user, declared_params(include_missing: false))
    .execute

  if result[:status] == :success
    present result[:release], with: Entities::Release
  else
    render_api_error!(result[:message], result[:http_status])
  end
end
```

Adapter：**Grape params、job token 策略、JSON Entity**。不含 tag 创建与 Evidence 逻辑。

### 5.2 Primary Adapter — GraphQL

```ruby
# app/graphql/mutations/releases/create.rb
def resolve(project_path:, assets: nil, **scalars)
  project = authorized_find!(project_path)
  params = { **scalars, assets: assets.to_h }.with_indifferent_access
  result = ::Releases::CreateService.new(project, current_user, params).execute
  # → { release:, errors: }
end
```

`authorize :create_release` 在 mutation 层；业务权限仍在 Service 内 `allowed?` 双检。

### 5.3 Use Case — `Releases::CreateService`

```ruby
def execute
  return error(..., 403) unless allowed?
  return error(..., 403) unless can_create_tag?
  return error(_('Release already exists'), 409) if release

  evidence_pipeline = Releases::EvidencePipelineFinder.new(project, params).execute
  tag = ensure_tag
  return tag unless tag.is_a?(Gitlab::Git::Tag)

  create_release(tag, evidence_pipeline)
end
```

| 步骤 | 职责 | 分层归属 |
|------|------|----------|
| 权限 | `:create_release`、protected tag | Service |
| 幂等/冲突 | 同 tag 已有 Release → 409 | Service + Model 唯一约束 |
| Milestone 校验 | 标题/id 必须存在 | Service + MilestonesFinder |
| Evidence 预取 | **tag 创建前**找 pipeline | Finder（只读） |
| Tag | 已有或 `Tags::CreateService` | 跨 BC Service |
| 持久化 | `build_release` + `save!` | Service 编排 + Model 校验 |
| 副作用 | 通知、hook、Worker、audit | Service |

**返回值**：Hash 风格 `ServiceResponse`（`success` / `error`，含 `http_status`）——与 Issue 一致，与 Project 老风格不同。

### 5.4 参数 ACL — `Releases::Links::Params`

创建时 assets.links 经白名单过滤，**防腐** HTTP 字段：

```ruby
# app/services/releases/links/params.rb
params.slice(:name, :url, :link_type).tap { |h| h[:filepath] = filepath if ... }
```

Adapter 传原始 hash → Service 内 Params 对象 → Model nested attributes。

### 5.5 Finder — `EvidencePipelineFinder`

```ruby
def execute
  sha = existing_tag&.dereferenced_target&.sha
  sha ||= repository&.commit(ref)&.sha
  project.ci_pipelines.for_sha(sha).last
end
```

**为何在 CreateService 内、且先于 tag 创建？**

源码注释：新建 tag 可能触发 pipeline，此时 Evidence 尚无数据；须在 tag 创建 **之前** 锁定 pipeline 快照。

Finder **只读、无副作用**，符合 `app/finders/` 定位。

### 5.6 跨 BC — `Tags::CreateService`

```ruby
def create_tag
  return error('Ref is not specified', 422) unless ref
  result = Tags::CreateService.new(project, current_user).execute(tag_name, ref, tag_message)
  return result unless result[:status] == :success
  result[:tag]
end
```

Release Service **编排** Repositories BC；Gitaly RPC 在 `project.repository.add_tag` → Client 层（见 [Release §5.6](/posts/gitlab-release/#56-client-与-service-的分工)）。

### 5.7 Model — `Release`

```ruby
# app/models/release.rb
validates :project, :tag, presence: true
validates :tag, uniqueness: { scope: :project_id }
validate :sha_unchanged, on: :update

accepts_nested_attributes_for :links, allow_destroy: true
before_create :set_released_at
```

Service 中 `build_release` 写入 `sha: tag.dereferenced_target.sha`——**创建时绑定 commit，之后不可改**（Model 不变量）。

`Release#sources`（PORO）在 **读取** 时计算，创建流程不持久化 Sources。

### 5.8 创建后副作用

```ruby
def create_release(tag, evidence_pipeline)
  release = build_release(tag)
  # optional Catalog...
  release.save!
  notify_create_release(release)
  execute_hooks(release, 'create')
  create_evidence!(release, evidence_pipeline)  # Worker unless historical/upcoming
  audit(release, action: :created)
  success(tag: tag, release: release)
end
```

| 同步 | 异步 |
|------|------|
| `save!`、webhook、`execute_hooks` | `NotificationService.new.async` |
| audit（EE） | `CreateEvidenceWorker` → `CreateEvidenceService` |

```ruby
def create_evidence!(release, pipeline)
  return if release.historical_release? || release.upcoming_release?
  ::Releases::CreateEvidenceWorker.perform_async(release.id, pipeline&.id)
end
```

Evidence 序列化在 Worker 内调 `Evidences::EvidenceSerializer`——**重 IO 离 request 路径**。

### 5.9 `Releases::BaseService`

共享 **非创建专属** 逻辑：`tag_name`、`milestones`（经 `MilestonesFinder`）、`existing_tag`、`execute_hooks` 委托 `release.execute_hooks`。

Create / Update / Destroy 继承同一 Base，避免重复参数解析。

---

## 6. 跨上下文协作

| 协作 | 调用 | BC |
|------|------|-----|
| `Tags::CreateService` | `ensure_tag` | **Repositories** |
| `MilestonesFinder` | milestone 校验与关联 | **Team Planning / Milestones** |
| `Ci::Catalog::Resources::ReleaseService` | Catalog 发布 | **CI Catalog** |
| `Discussions::…` | —（创建 Release 不涉及） | — |
| `project.ci_pipelines` | EvidencePipelineFinder | **CI** |
| `NotificationService` | 邮件等 | 出站 Adapter |
| `Gitlab::HookData::ReleaseBuilder` | webhook payload（经 Model） | 出站 Adapter |

Release 创建 **不** 直接调用 `GitalyClient`；Git 操作经 `Tags::CreateService` 与 `repository.find_tag`。

---

## 7. 符合的架构原则

### 7.1 官方抽象复用规则

| 原则 | Release 创建中的体现 |
|------|---------------------|
| **Use-case 导向** | `CreateService#execute`，非 `Release.create` |
| **一用例一 Service** | 创建 vs `Links::CreateService`（单独加 link） |
| **Finder 只读** | `EvidencePipelineFinder`、列表用 `ReleasesFinder` |
| **权限在 Service** | `allowed?`、`can_create_tag?` |
| **参数白名单** | `Links::Params` |
| **Worker 异步** | `CreateEvidenceWorker` |
| **Adapter 薄** | REST/GraphQL 只调 Service + present |

### 7.2 Clean Architecture / 六边形

| 概念 | Release 创建 |
|------|-------------|
| Entity | `Release`、`Releases::Link` |
| Use Case | `Releases::CreateService` |
| Query | `EvidencePipelineFinder`、`MilestonesFinder` |
| Primary Adapter | REST、GraphQL、TagsController |
| Secondary Adapter | Notification、Webhook、ActiveRecord、Gitaly（经 Tags） |

### 7.3 DDD 战术

| 模式 | 体现 |
|------|------|
| **Aggregate Root** | `Release` + nested links |
| **ACL** | `Links::Params` |
| **Application Service** | `CreateService` |
| **CQRS** | 写 `CreateService` / 读 `ReleasesFinder` |
| **Domain 不变量** | tag 唯一、`sha` 不可改（update 时） |

创建时 **不** 发布 `ReleasePublishedEvent`（该事件用于 **upcoming release 到点发布**，见 `PublishEventWorker`）。

---

## 8. 与 Issue / Project 创建对比

| 维度 | Release 创建 | Issue 创建 | Project 创建 |
|------|-------------|-----------|--------------|
| Bounded Context | `Releases` | `WorkItems` | `Projects` |
| 返回值 | `ServiceResponse` (Hash) | `ServiceResponse` | `Project` |
| 构建拆分 | 内联 `build_release` | `BuildService` + `create` | 内联 `Project.new` |
| 共享基类 | `Releases::BaseService` | `IssuableBaseService` | 老 `BaseService` |
| 外部 Git | **Tags::CreateService** | 无 | **create_repository** |
| Finder 参与写路径 | **EvidencePipelineFinder** | EvidencePipelineFinder 类似 | 无 |
| GraphQL | ✓ `ReleaseCreate` | ✓ `CreateIssue` | CE 无 |
| 典型异步 | `CreateEvidenceWorker` | `NewIssueWorker` | `PostCreationWorker` |
| Nested 创建 | links via nested attributes | — | — |

**Release 独特点**：必须先 resolve **Git tag + sha**，再写 DB；Evidence pipeline 须在 tag 创建前锁定。

---

## 9. 关键路径速查

| 类别 | 路径 |
|------|------|
| Bounded Context | `config/bounded_contexts.yml` → `Releases:` |
| **创建用例** | `app/services/releases/create_service.rb` |
| 基类 | `app/services/releases/base_service.rb` |
| Link ACL | `app/services/releases/links/params.rb` |
| Evidence Finder | `app/finders/releases/evidence_pipeline_finder.rb` |
| 聚合根 | `app/models/release.rb` |
| Tag 子用例 | `app/services/tags/create_service.rb` |
| **REST 入口** | `lib/api/releases.rb` |
| **GraphQL 入口** | `app/graphql/mutations/releases/create.rb` |
| Evidence Worker | `app/workers/releases/create_evidence_worker.rb` |
| Evidence 用例 | `app/services/releases/create_evidence_service.rb` |
| Hook Builder | `lib/gitlab/hook_data/release_builder.rb` |
| Spec | `spec/services/releases/create_service_spec.rb` |

---

## 10. 阅读建议

1. **从 REST POST 跟到 `create_release`**：`lib/api/releases.rb` → `CreateService#execute`。
2. **理解 `EvidencePipelineFinder` 顺序**：为何在 `ensure_tag` 之前。
3. **对比 Tag 两种路径**：`existing_tag` vs `Tags::CreateService`。
4. **跟踪 Evidence**：`CreateEvidenceWorker` → `CreateEvidenceService`。
5. **跑 spec**：`bundle exec rspec spec/services/releases/create_service_spec.rb`。

**延伸阅读**：[Release 完整文档](/posts/gitlab-release/) · [§13 端到端调用链](/posts/gitlab-release/#13-端到端调用链) · [Source PORO §5.2](/posts/gitlab-release/#52-releasessource-poro)
