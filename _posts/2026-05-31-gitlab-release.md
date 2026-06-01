---
title: "GitLab Release：概念、代码实现与 DDD 分析"
date: 2026-05-31 10:00:00 +0800
categories: [GitLab, Releases, DDD]
tags: [release, domain-driven-design, bounded-context, aggregate, use-case, finder, release-evidence, release-assets]
description: >-
  说明 GitLab Release 的产品含义、代码分层（Model / Service / Client / Finder / API）、各功能实现路径，以及 Releases:: 限界上下文中的 DDD 战术模式。
---

> 本文基于 GitLab 源码（`gitlab-org/gitlab`）与官方设计文档整理。  
> 分析日期：2026-05-31  
> **创建流程分层专文**：[Release 创建：代码分层与架构原则](/posts/gitlab-release-create-layering/)

## 目录

1. [Release 是什么](#1-release-是什么)
2. [Release 与 Git Tag 的关系](#2-release-与-git-tag-的关系)
3. [代码架构总览](#3-代码架构总览)
4. [Releases:: 限界上下文](#4-releases-限界上下文)
5. [领域层：模型与聚合](#5-领域层模型与聚合)
5.2. [`Releases::Source` PORO](#52-releasessource-poro)
5.5. [Model 与 Service 的分工](#55-model-与-service-的分工)
5.6. [Client 与 Service 的分工](#56-client-与-service-的分工)
6. [领域层：Use Case（app/services/releases/）](#6-领域层use-caseappservicesreleases)
7. [领域层：查询对象（app/finders/）](#7-领域层查询对象appfinders)
8. [应用层：入口适配器](#8-应用层入口适配器)
9. [各功能代码实现](#9-各功能代码实现)
10. [DDD 概念映射](#10-ddd-概念映射)
11. [权限模型](#11-权限模型)
12. [架构关系图](#12-架构关系图)
13. [端到端调用链](#13-端到端调用链)
14. [与 Textbook DDD 的对照](#14-与-textbook-ddd-的对照)
15. [关键路径速查](#15-关键路径速查)
16. [阅读建议](#16-阅读建议)

---

## 1. Release 是什么

GitLab 官方文档（`doc/user/project/releases/_index.md`）的定义：

> Create a release to package your project at critical milestones. Releases combine code, binaries, documentation, and release notes into a complete snapshot of your project.

可以概括为：

**Release = 在某个 Git tag 上，附加名称、说明、资产、里程碑、审计证据等信息的「版本交付记录」。**

对用户而言，Release 页面回答三个问题：

1. **这个版本对应哪段代码？** → 绑定 Git tag 和 commit SHA
2. **这个版本有什么说明和下载物？** → description、Links、Sources
3. **这个版本如何被追溯？** → Evidence、Webhook、Audit

---

## 2. Release 与 Git Tag 的关系

| 层次 | 对象 | 存储位置 |
|------|------|----------|
| Git 层 | Tag → Commit | Gitaly（仓库） |
| GitLab 层 | Release 记录 | PostgreSQL `releases` 表 |

代码约束（`app/models/release.rb`）：

```ruby
validates :project, :tag, presence: true
validates :tag, uniqueness: { scope: :project_id }
validate :sha_unchanged, on: :update
```

含义：

- 每个项目内，一个 tag 只能对应一个 Release
- Release 创建时写入 `sha`（tag 指向的 commit），之后 **不允许修改**
- 若 tag 不存在，创建 Release 时可传 `ref`，由 `Tags::CreateService` 先创建 tag
- 删除 Git tag 会连带删除 Release（产品文档 warning）

---

## 3. 代码架构总览

Release 相关代码按 **职责** 分为四层：

```
                    用户 / 客户端
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
   Controller         REST API          GraphQL        ← 应用层（入口适配器）
        │                │                │
        └────────────────┼────────────────┘
                         │ 调用
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
   *Service           Finder            Worker         ← 领域层（用例 / 查询 / 异步）
        │                │
        ▼                ▼
   Release AR         Release scope                      ← 领域层（模型）
```

| 层次 | 路径 | 职责 | 读/写 |
|------|------|------|-------|
| **模型** | `app/models/release.rb`、`app/models/releases/` | Entity、聚合、校验规则 | 读写基础 |
| **Use Case** | `app/services/releases/` | 完成一个业务动作（创建、更新、删链等） | **写 + 副作用** |
| **查询对象** | `app/finders/releases*` | 复杂只读查询（列表、找 pipeline） | **只读** |
| **异步** | `app/workers/releases/` | 证据收集、发布 Event 等后台任务 | 写 |
| **REST 适配器** | `lib/api/releases.rb` | HTTP API 参数解析、鉴权、调 Service/Finder | — |
| **GraphQL 适配器** | `app/graphql/mutations/releases/` | GraphQL 参数解析、鉴权、调 Service | — |
| **Web 适配器** | `app/controllers/projects/releases*` | HTML 页面、RSS、下载跳转 | — |

GitLab 官方设计（`doc/development/software_design.md`）强调：**按 use case 设计，而不是把逻辑堆在 Entity 的 CRUD 上**。因此 `app/services/releases/` 是 Release 业务动作的 **核心编排层**。

---

## 4. Releases:: 限界上下文

`Releases::` 在 `config/bounded_contexts.yml` 注册，关联 feature categories：

- `release_orchestration` — 发布编排
- `release_evidence` — 发布证据收集

### 4.1 边界

**属于 `Releases::`**：Release 本身的生命周期、资产链接、发布证据。

**不属于 `Releases::`**（通过协作接入）：

| 外部上下文 | 协作方式 | 示例 |
|------------|----------|------|
| `Tags::` | Service 调用 | `Tags::CreateService` 创建 tag |
| `Ci::` | Finder + Worker | `EvidencePipelineFinder` 查 pipeline |
| `Ci::Catalog::` | Service 调用 | Catalog 发布 |
| `Projects::` | Event 归属 | `Projects::ReleasePublishedEvent` |
| `Repositories::` | 委托 | `release.commit` → `project.repository` |
| `Packages::` | 查询 | `tagged_packages` |

**设计信号**：`ReleasePublishedEvent` 放在 `Projects::` 而非 `Releases::`，因为订阅方从 **Project 视角** 响应「某项目发布了 Release」。

### 4.2 目录结构（按层标注）

```
# ── 领域层 · 模型 ──
app/models/
├── release.rb
└── releases/
    ├── link.rb
    ├── evidence.rb
    └── source.rb

# ── 领域层 · Use Case ──
app/services/releases/
├── base_service.rb                 # 共享参数解析（非独立用例）
├── create_service.rb
├── update_service.rb
├── destroy_service.rb
├── create_evidence_service.rb
└── links/                          # 链接 CRUD 子用例

# ── 领域层 · 查询对象 ──
app/finders/
├── releases_finder.rb
└── releases/
    ├── group_releases_finder.rb
    └── evidence_pipeline_finder.rb

# ── 领域层 · 异步 ──
app/workers/releases/

# ── 应用层 · 入口（不受 bounded context 强制）──
lib/api/releases.rb
app/graphql/mutations/releases/
app/controllers/projects/releases_controller.rb
```

数据库表（`db/docs/`）：

| 表 | 模型 | 说明 |
|----|------|------|
| `releases` | `Release` | 主记录，`project_id` 分片键 |
| `release_links` | `Releases::Link` | 资产链接 |
| `evidences` | `Releases::Evidence` | 发布证据 JSON |
| `milestone_releases` | `MilestoneRelease` | Release ↔ Milestone 关联 |

---

## 5. 领域层：模型与聚合

### 5.1 聚合根 `Release`

```ruby
# app/models/release.rb
class Release < ApplicationRecord
  belongs_to :project
  belongs_to :author, class_name: 'User'

  has_many :links, class_name: 'Releases::Link'
  has_many :evidences, class_name: 'Releases::Evidence'
  has_many :milestones, through: :milestone_releases

  accepts_nested_attributes_for :links, allow_destroy: true

  validates :tag, uniqueness: { scope: :project_id }
  validate :sha_unchanged, on: :update
end
```

**聚合边界**：

```
Release (Aggregate Root)
├── Releases::Link          ← Entity（release_links 表）
├── Releases::Evidence      ← Entity（evidences 表）
├── MilestoneRelease        ← 关联表（跨 Milestone 上下文）
└── Releases::Source        ← PORO（运行时计算，无表）

外部引用：
├── Project                 ← tenant 容器
├── Git Tag                 ← Repositories::
└── Ci::Pipeline            ← 证据收集时引用
```

**不变量**：`(project_id, tag)` 唯一；`sha` 创建后不可改；Link 的 `(name, url, filepath)` 在 release 内不可重复。

### 5.2 `Releases::Source` PORO

`app/models/releases/source.rb` 是一个 **无数据库表的 PORO（Plain Old Ruby Object）**，表示 Release 附带的 **源码归档下载项（Source code archive）**——不是 `releases` 或 `release_links` 表里的记录，而是根据 `project` + `tag` **运行时推导** 出来的值对象。

#### 产品含义

Release 页面和 API 的 **Assets** 分两类：

| 类型 | 模型 | 存储 | 含义 |
|------|------|------|------|
| **Links** | `Releases::Link` | `release_links` 表 | 用户/API 自定义外链（安装包、镜像、Runbook 等） |
| **Sources** | `Releases::Source` | **不存库** | 固定几种格式的 **Git 仓库源码压缩包** |

Sources 回答：「这个 tag 对应的代码，以 zip/tar 等形式从哪里下载？」

#### 实现要点

```ruby
# app/models/releases/source.rb
module Releases
  class Source
    include ActiveModel::Model

    attr_accessor :project, :tag_name, :format

    def self.all(project, tag_name)
      Gitlab::Workhorse::ARCHIVE_FORMATS.map do |format|
        new(project: project, tag_name: tag_name, format: format)
      end
    end

    def url
      Gitlab::Routing.url_helpers.project_archive_url(
        project,
        id: File.join(tag_name, archive_prefix),
        format: format
      )
    end

    def hook_attrs
      { format: format, url: url }
    end

    private

    def archive_prefix
      "#{project.path}-#{tag_name.tr('/', '-')}"
    end
  end
end
```

| 方法 | 作用 |
|------|------|
| `.all(project, tag)` | 为 Workhorse 支持的每种格式各建一个实例（通常 4 个） |
| `#url` | 生成归档下载 URL，如 `…/-/archive/v1.0/app-v1.0.zip` |
| `#archive_prefix` | tag 含 `/` 时转为 `-`（`beta/v1.0` → `app-beta-v1.0`） |
| `#hook_attrs` | Webhook payload 用的 `{ format:, url: }` |

支持的格式（`Gitlab::Workhorse::ARCHIVE_FORMATS`）：`zip`、`tar.gz`、`tar.bz2`、`tar`。

#### 聚合根如何暴露

```ruby
# app/models/release.rb
def sources
  strong_memoize(:sources) do
    Releases::Source.all(project, tag)
  end
end

def assets_count(except: [])
  links_count = links.size
  sources_count = except.include?(:sources) ? 0 : sources.size
  links_count + sources_count
end
```

`Release#sources` 是聚合的一部分，但 **不落库**——每次访问时按 tag 重新计算 URL（结果 memoize 在 Release 实例上）。

#### 消费方

```
Release#sources
    ├── REST API     lib/api/entities/release.rb  → assets.sources（需 :read_code 权限）
    ├── Webhook      Gitlab::HookData::ReleaseBuilder  → sources: release.sources.map(&:hook_attrs)
    └── 资产计数     Release#assets_count
```

REST 序列化（`lib/api/entities/releases/source.rb`）只暴露 `format` 和 `url` 两个字段。

#### 为什么做成 PORO 而不是 Entity

- **无独立生命周期**：不需要 CRUD Service，没有 `Sources::CreateService`
- **完全由 tag 推导**：tag 定了，sources 内容和数量就定了
- **与 Links 对比**：Links 是用户输入、需校验和持久化；Sources 是产品内置能力、只算 URL

这是典型的 **Value Object**：封装「有哪些格式、下载地址怎么拼」，放在 `app/models/releases/` 是因为它是 **Release 聚合内的概念**，不是跨上下文的通用 Client。

#### 架构注记

- `#url` 依赖 `Gitlab::Routing`（路由 helper），带一点基础设施耦合——GitLab pragmatic 妥协，和 `Releases::Source` 作为 PORO 放在 Model 层的惯例一致
- 实际下载由 **Workhorse** 代理 Git 归档流，PORO 只负责 **生成可访问的 URL**，不参与打包过程

---

## 5.5 Model 与 Service 的分工

GitLab 官方设计（`doc/development/software_design.md`）强调：**按 use case 设计，不要把无关逻辑堆在 Entity 的 CRUD 上**。

| 写在哪里 | 回答的问题 |
|----------|------------|
| **Model** | 这个对象 **是什么**？有哪些 **不变量** 和 **只属于它自己的行为**？ |
| **Service** | 这个 **用例** 要做什么？涉及 **哪些对象、权限、副作用、跨上下文协作**？ |

### 什么写在 Model 里

适合放在 `app/models/`（Entity / PORO）：

**1. 数据不变量（校验规则）**

```ruby
# app/models/release.rb
validates :tag, uniqueness: { scope: :project_id }
validate :sha_unchanged, on: :update
```

**2. 只依赖自身字段/关联的领域行为**

```ruby
def name
  self.read_attribute(:name) || tag
end

def upcoming_release?
  released_at.present? && released_at.to_i > Time.zone.now.to_i
end
```

**3. 聚合内 Entity 的规则**

```ruby
# app/models/releases/link.rb
validates :url, presence: true, uniqueness: { scope: :release }
enum :link_type, { other: 0, runbook: 1, package: 2, image: 3 }
```

**4. 领域规则（含脱敏等对象自身语义）**

```ruby
# app/models/releases/evidence.rb
def summary
  safe_summary.dig('release', 'milestones')&.each { |m| m.delete('issues') }
  safe_summary
end
```

**5. 无表的 PORO / 值对象式逻辑**

```ruby
# app/models/releases/source.rb — 运行时计算 archive URL（详见 §5.2）
Releases::Source.all(project, tag_name)  # → [Source(zip), Source(tar.gz), …]
source.url  # → …/-/archive/v1.0/app-v1.0.zip
```

**6. Active Record 关联、scope**

```ruby
has_many :links, class_name: 'Releases::Link'
scope :sorted, -> { order(released_at: :desc) }
```

### 什么写在 Service 里

适合放在 `app/services/<context>/`（Use Case）：

**1. 完整业务用例（一个用户动作）**

```ruby
# app/services/releases/create_service.rb
def execute
  return error(...) unless allowed?
  evidence_pipeline = EvidencePipelineFinder.new(...).execute
  tag = ensure_tag
  create_release(tag, evidence_pipeline)  # 保存 + 通知 + webhook + Worker + audit
end
```

**2. 权限 / 前置条件**

```ruby
def allowed?
  Ability.allowed?(current_user, :create_release, project)
end
```

**3. 跨上下文协作**

```ruby
Tags::CreateService.new(...).execute(...)
Ci::Catalog::Resources::ReleaseService.new(...).execute
```

Model 不应直接知道 Tags、Ci、Catalog 等其他限界上下文。

**4. 副作用编排**

```ruby
release.save!
NotificationService.new.async.send_new_release_notifications(release)
release.execute_hooks('create')
Releases::CreateEvidenceWorker.perform_async(release.id, pipeline&.id)
audit(release, action: :created)
```

**5. 事务边界**

```ruby
# app/services/releases/update_service.rb
ApplicationRecord.transaction do
  release.update(params)
  execute_hooks(release, 'update')
end
```

**6. 子用例（意图不同就拆 Service）**

```ruby
# app/services/releases/links/create_service.rb — 单独「添加链接」
```

**7. 参数白名单**

```ruby
# app/services/releases/links/params.rb
params.slice(:name, :url, :link_type)
```

### 对照表

| 场景 | Model | Service | Finder |
|------|-------|---------|--------|
| 字段格式、唯一性校验 | ✓ | | |
| 基于自身属性的计算 | ✓ | | |
| 关联、scope | ✓ | | |
| 创建/更新/删除 **整个用例** | | ✓ | |
| 权限检查 | | ✓ | |
| 调其他 BC 的 Service | | ✓ | |
| Event、Worker、通知、审计 | | ✓（编排） | |
| Transaction | | ✓ | |
| 复杂只读列表 | | | ✓ |
| HTTP 参数解析 | | | Adapter 层 |

### Release 实例对照

| 逻辑 | 位置 | 原因 |
|------|------|------|
| `sha` 不可改 | `Release` Model | 不变量 |
| `upcoming_release?` | `Release` Model | 自身属性判断 |
| Link URL 校验 | `Releases::Link` Model | 子 Entity 规则 |
| 创建 tag + 保存 + webhook | `CreateService` | 用例编排 |
| 检查 `:create_release` | `CreateService` | 用例权限 |
| 找 evidence pipeline | `EvidencePipelineFinder` | 只读查询 |
| 单独 CRUD link | `Links::CreateService` | 独立子用例 |

### 灰色地带（GitLab pragmatic 妥协）

**Model 里的出站调用** — `Release#execute_hooks` 调 `HookData::ReleaseBuilder` 和 webhook。严格分层下应在 Service；GitLab 允许 Entity 触发，主链路仍由 Service 编排。

**同一 Entity、两个用例入口** — 创建 Release 时 nested attributes 带 links；单独 API 走 `Links::CreateService`。

**上帝对象** — `Project` 4000+ 行是历史遗留。官方指南：新行为优先放 dedicated class / Service，见 [Taming Omniscient Classes](https://gitlab.com/gitlab-org/gitlab/-/blob/master/doc/development/software_design.md#taming-omniscient-classes)。

### 决策流程（写新代码时）

```
新逻辑来了
    │
    ├─ 只涉及单个 Entity 的不变量 / 自身行为？ → Model（或 PORO）
    ├─ 完整用例（权限 + 多步 + 副作用）？       → Service
    ├─ 只是复杂查询、不改数据？                 → Finder
    ├─ HTTP/JSON 格式转换？                     → Controller / API Entity / Presenter
    └─ 跨 BC 且要解耦？                         → EventStore 或调用对方 Service
```

---

## 5.6 Client 与 Service 的分工

GitLab 官方（`doc/development/software_design.md`）把代码分为 **领域代码**（描述 GitLab 产品业务）和 **通用/基础设施代码**（Client、Logger、Redis 工具等）。Client 属于后者，Service 属于前者。

| 写在哪里 | 回答的问题 |
|----------|------------|
| **Client** | **怎么** 和外部系统通信？（协议、认证、重试、超时） |
| **Service** | 这个 **用例** 要做什么？**何时** 调外部系统、**为何** 调、失败时业务上怎么处理？ |

Client 是六边形架构里的 **Secondary Adapter（被驱动侧）** 最底层；Service 是 **Application Core（用例）**，通过中间封装间接使用 Client，而不是自己发 gRPC/HTTP。

### 什么写在 Client 里

适合放在 `lib/gitlab/**/client.rb`、`lib/gitlab/gitaly_client/` 等 **基础设施层**：

**1. 连接、认证、协议细节**

```ruby
# lib/gitlab/github_import/client.rb — HTTP + Octokit
def initialize(token, host: nil, per_page: DEFAULT_PER_PAGE, parallel: true)
  @octokit = ::Octokit::Client.new(access_token: token, api_endpoint: api_endpoint, ...)
end
```

**2. 远程调用与序列化（gRPC / HTTP body）**

```ruby
# lib/gitlab/gitaly_client/repository_service.rb
def exists?
  request = Gitaly::RepositoryExistsRequest.new(repository: @gitaly_repo)
  response = gitaly_client_call(@storage, :repository_service, :repository_exists, request,
    timeout: GitalyClient.fast_timeout)
  response.exists
end
```

**3. 重试、超时、限流、连接池**

```ruby
# lib/gitlab/gitaly_client.rb — CLIENT_RETRY_DEFAULT_MAX_ATTEMPTS、stub 缓存
# lib/gitlab/github_import/client.rb — RATE_LIMIT_THRESHOLD、with_rate_limit
```

**4. 把底层错误翻译成可捕获的异常类型**

```ruby
# lib/gitlab/git/wraps_gitaly_errors.rb — gRPC → Gitlab::Git::Repository::TagExistsError
```

**5. 与具体 datastore / 外部 SaaS 绑定的读写**

| Client | 外部系统 |
|--------|----------|
| `Gitlab::GitalyClient::*Service` | Gitaly（Git 仓库 gRPC） |
| `Gitlab::GithubImport::Client` | GitHub REST API |
| `Gitlab::Kubernetes::KubeClient` | Kubernetes API |
| `Gitlab::Lfs::Client` | LFS 存储 |
| `Import::Clients::ObjectStorage` | S3 / 对象存储 |

**Client 里不应有**：权限检查（`Ability.allowed?`）、用例编排、Webhook/通知、Audit、跨 BC 业务规则。

### 什么写在 Service 里

`app/services/<context>/` 的 Use Case **调用** Client（通常不直接 `new GitalyClient`，见下文中间层），但 **不实现** 传输细节：

**1. 决定何时、为何调用外部能力**

```ruby
# app/services/releases/create_service.rb
def create_tag
  return error('Ref is not specified', 422) unless ref

  result = Tags::CreateService.new(project, current_user).execute(tag_name, ref, tag_message)
  return result unless result[:status] == :success
  result[:tag]
end
```

**2. 业务前置条件与权限**

```ruby
def can_create_tag?
  ::Gitlab::UserAccess.new(current_user, container: project).can_create_tag?(tag_name)
end
```

**3. 把 Client/Adapter 失败映射为业务错误**

```ruby
# app/services/tags/create_service.rb
begin
  new_tag = repository.add_tag(current_user, tag_name, target, message)
rescue Gitlab::Git::Repository::TagExistsError
  return error("Tag #{tag_name} already exists", 409)
rescue Gitlab::Git::PreReceiveError => ex
  return error(ex.message)
end
```

**4. 编排 Model + 其他 Service + 副作用**

Service 知道「创建 Release 要先 ensure tag、再 save、再 webhook」；Client 只知道「向 Gitaly 发 create_tag RPC」。

**5. 不含 wire 细节**

Service **不应** 直接构造 `Gitaly::RepositoryExistsRequest`、解析 Octokit 分页、配置 gRPC channel——这些属于 Client 或 Client 之上的封装层。

### 中间层：`Gitlab::Git::Repository`（Secondary Adapter 封装）

GitLab 通常不让 Service 直接碰 `GitalyClient`，中间有一层 **领域友好的 Git 封装**：

```
Service                    Secondary Adapter              Client
Tags::CreateService   →   Gitlab::Git::Repository   →   GitalyClient::RefService
                          project.repository.add_tag      gitaly_client_call(...)
```

```ruby
# lib/gitlab/git/repository.rb — 对外是「Git 仓库」语义，对内委托 GitalyClient
def add_tag(...)
  gitaly_operation_client.user_create_tag(...)
end
```

这层负责：把 protobuf/commit SHA 等细节藏起来，抛出 `TagExistsError` 等领域相关异常。  
**新 Git 操作**：RPC 细节进 `GitalyClient::*Service`；Repository 暴露语义化方法；Service 只调 `repository.xxx`。

### Client / Service / Model 对照表

| 场景 | Client | Service | Model |
|------|--------|---------|-------|
| gRPC 超时、重试 | ✓ | | |
| GitHub API 限流 | ✓ | | |
| Octokit / protobuf 请求体 | ✓ | | |
| `can_create_tag?` 权限 | | ✓ | |
| 创建 Release 完整用例 | | ✓ | |
| tag 唯一性（DB） | | | ✓ |
| `sha` 不可改 | | | ✓ |
| 何时创建 tag | | ✓ | |
| 如何发 create_tag RPC | ✓ | | |
| Tag 已存在 → 409 响应 | | ✓（映射错误） | |

### Release 端到端示例

创建 Release 且 tag 不存在时：

```
lib/api/releases.rb  (Primary Adapter)
    → Releases::CreateService#execute          ← 用例：权限、找 pipeline、编排
        → Tags::CreateService#execute           ← 子用例：创建 Git tag
            → project.repository.add_tag        ← Git 封装（非 Client 命名，但是出站 Adapter）
                → GitalyClient::OperationService ← Client：gRPC
        → release.save!                         ← DB（ActiveRecord Adapter）
        → NotificationService / execute_hooks   ← 其他出站 Adapter
```

读 commit SHA（Evidence / 校验）：

```
EvidencePipelineFinder
    → repository.commit(ref)     ← Gitlab::Git::Repository
        → GitalyClient::CommitService
```

**规律**：Service/Finder 停在 `repository` 或 `project` 领域 API；**不 import** `Gitlab::GitalyClient`。

### 与 REST「API Client」的区别

| 名称 | 含义 | 路径 |
|------|------|------|
| **Infrastructure Client** | 出站：Rails 调 Gitaly/GitHub/K8s | `lib/gitlab/**/client.rb` |
| **REST API（Primary Adapter）** | 入站：外部 HTTP 调 GitLab | `lib/api/releases.rb` |
| **前端 API client** | 浏览器/CLI 调 GitLab REST | 不在 Rails 后端 |

本文 §5.6 的 **Client** 指 **基础设施出站 Client**，不是 `lib/api/` 也不是前端 SDK。

### 灰色地带

**Service 里 `rescue Gitlab::Git::*`** — 异常类型由 Client/Repository 层定义，Service 负责转成 `ServiceResponse`；业务语义在 Service，错误分类在 Git 封装层。

**`Import::Clients::ObjectStorage` 在 Service 内 `new`** — Import 用例直接持有 Client 实例较常见；仍保持 Client 只做存储读写，导入策略与 ACL 在 Service/Representation。

**`Gitlab::GitalyClient` 在个别 Service 里被直接引用** — 如 `Import::ValidateRemoteGitEndpointService` 做存在性探测；属 pragmatic 例外，新代码优先走 `Gitlab::Git::Repository` 或专用封装。

### 决策流程（写新代码时）

```
需要和外部系统通信
    │
    ├─ 只是协议/连接/重试/序列化？              → Client（lib/gitlab/）
    ├─ 已有 Repository / 封装类暴露语义化 API？ → Service 调封装，不碰 Client
    ├─ 新 Git 操作？                            → GitalyClient 方法 + Repository 包装 + Service 编排
    ├─ 完整业务用例（权限+多步+副作用）？       → Service（app/services/）
    └─ 外部 JSON → 领域对象？                   → Representation / ACL，再进 Service
```

---

## 6. 领域层：Use Case（app/services/releases/）

### 6.1 是什么

`app/services/releases/` 下的类是 GitLab 对 **Use Case（用例）** 的实现方式。GitLab 没有单独的 `UseCase` 类，而是用 **Service Object**，每个类对应一个 **完整的业务动作**，而非简单的 `Release.create`。

官方文档（`doc/development/software_design.md`）：

> Design around use cases instead of entities. … A different service object that embeds the specific permissions and a cohesive set of parameters.

### 6.2 用例映射

| 文件 | 实现的用例 | 读/写 |
|------|-----------|-------|
| `create_service.rb` | **创建 Release**（可创建 tag、挂 milestone、触发 webhook/evidence） | 写 |
| `update_service.rb` | **更新 Release** | 写 |
| `destroy_service.rb` | **删除 Release** | 写 |
| `create_evidence_service.rb` | **收集发布证据**（常由 Worker 调用） | 写 |
| `links/create_service.rb` | **添加资产链接** | 写 |
| `links/update_service.rb` | **更新链接** | 写 |
| `links/destroy_service.rb` | **删除链接** | 写 |
| `base_service.rb` | **不是用例** — 共享 tag/ref/milestone 解析 | — |

### 6.3 为什么算 Use Case，而不只是 CRUD

`CreateService#execute` 远不止 `Release.create`：

```ruby
def execute
  return error(...) unless allowed?              # 权限
  return error(...) unless can_create_tag?       # tag 保护
  return error(...) if release                   # 已存在

  evidence_pipeline = EvidencePipelineFinder...  # 跨上下文
  tag = ensure_tag                               # Tags::CreateService
  create_release(tag, evidence_pipeline)         # 持久化 + 通知 + webhook + Worker + audit
end
```

一个 Service 封装：**前置条件 → 编排 → 副作用**，这是 Application Service / Use Case 的典型职责。

### 6.4 命名约定

```ruby
# Good — 通用语言 + 用例
Releases::CreateService
Releases::Links::CreateService

# Bad — CRUD 泄漏
ReleaseLinks::CreateService
```

### 6.5 继承层次

```
Releases::BaseService              # 共享：tag/ref/milestone 解析、execute_hooks、audit
├── CreateService
├── UpdateService
├── DestroyService
└── CreateEvidenceService

Releases::Links::BaseService
├── CreateService
├── UpdateService
└── DestroyService
```

`base_service.rb` 提供 `release`、`existing_tag`、`milestones` 等查找，避免各用例重复代码。

### 6.6 Service 与 Finder 的区别

| | Service（Use Case） | Finder（查询对象） |
|---|---------------------|-------------------|
| 职责 | 完成业务动作 | 查数据、过滤、排序 |
| 读/写 | 读写 + 副作用 | **只读** |
| 副作用 | 通知、Webhook、Worker、Audit | 无 |
| 例子 | `CreateService` | `ReleasesFinder` |

---

## 7. 领域层：查询对象（app/finders/）

Finder **不是 Use Case**，专门封装 **怎么查 Release**，不写库、无业务副作用。

### 7.1 `releases_finder.rb`

项目下的 Release 列表，Controller 和 REST API 都会调用：

```ruby
ReleasesFinder.new(project, current_user, params).execute
```

职责：

- 按 project 过滤，检查 `:read_release` 权限
- 支持 tag 筛选、排序、`latest`、更新时间范围
- `preloaded` 预加载关联，避免 N+1

### 7.2 `releases/group_releases_finder.rb`

Group（及子 group）下所有项目的 Release 列表。跨 project 查询复杂，使用 `InOperatorOptimization` 优化性能。

### 7.3 `releases/evidence_pipeline_finder.rb`

**不面向用户的列表查询**，供 `CreateService` 内部使用：

```ruby
sha = existing_tag&.dereferenced_target&.sha
sha ||= repository&.commit(ref)&.sha
project.ci_pipelines.for_sha(sha).last
```

按 tag/ref 找到对应 CI pipeline，供 Evidence 快照引用。

### 7.4 只读调用链

```
GET /projects/:id/releases
    → lib/api/releases.rb 或 Controller#index
    → ReleasesFinder#execute
    → Release 模型 + scope
    → Serializer / Entity → JSON / HTML
```

---

## 8. 应用层：入口适配器

Application Layer **不受** `bounded_contexts.yml` 约束，按 **HTTP 入口 scope** 组织（如 `projects/releases`）。三者都是 **Primary Adapter（驱动适配器）**：把外部请求转成对 Service / Finder 的调用。

### 8.1 `lib/api/releases.rb` — REST API

面向 HTTP REST 客户端：Release CLI、CI job、第三方集成。

```
GET    /projects/:id/releases          → ReleasesFinder
POST   /projects/:id/releases          → Releases::CreateService
PUT    /projects/:id/releases/:tag     → Releases::UpdateService
DELETE /projects/:id/releases/:tag     → Releases::DestroyService
POST   .../assets/links                → Releases::Links::CreateService
```

API 层只做：解析参数 → 鉴权 → 调 Service/Finder → `Entities::Release` 序列化 JSON。**不含核心业务逻辑。**

### 8.2 `app/graphql/mutations/releases/` — GraphQL

前端通过 GraphQL 变更 Release：

```
mutations/releases/
├── base.rb      # 公共参数 project_path
├── create.rb    # ReleaseCreate
├── update.rb    # ReleaseUpdate
└── delete.rb    # ReleaseDelete
```

内部同样调用 `Releases::CreateService` 等，与 REST **共享同一套用例**，区别仅在协议和参数格式。

### 8.3 `app/controllers/projects/releases_controller.rb` — Web

面向浏览器（Deploy > Releases 页面）：

```ruby
def index
  # HTML / JSON / Atom RSS
  ReleasesFinder.new(@project, current_user, params).execute
end

def downloads
  # Direct Asset Path 下载跳转
  release.links.find_by_filepath!(...)
end

def latest_permalink
  # /releases/permalink/latest → 最新版本
end
```

Controller 额外处理 **HTML 渲染、RSS、下载 redirect** 等 Web 特有行为。

### 8.4 写操作调用链

```
POST /releases  或  GraphQL ReleaseCreate
    → lib/api/releases.rb 或 mutations/releases/create.rb
    → Releases::CreateService#execute          ← Use Case
    → Release.save! + Webhook + Worker + Audit
```

---

## 9. 各功能代码实现

### 9.1 创建 Release

创建时绑定 tag 与 sha（`create_service.rb`）：

```ruby
def build_release(tag)
  project.releases.build(
    tag: tag.name,
    sha: tag.dereferenced_target.sha,
    name: name,
    description: description,
    released_at: released_at,
    links_attributes: links_attributes,
    milestones: milestones
  )
end
```

完整流程见 [§6.3](#63-为什么算-use-case而不只是-crud) 与 [§13 端到端调用链](#13-端到端调用链)。

**Upcoming / Historical Release**：

```ruby
def upcoming_release?   # released_at 在未来 → 跳过 evidence
def historical_release? # released_at 早于 created_at → 跳过 evidence
```

### 9.2 Release Notes

| 字段 | 行为 |
|------|------|
| `name` | 为空时 fallback 到 `tag` |
| `description` | Markdown，`cache_markdown_field` 渲染 |

更新走 `UpdateService`，**不可改 `sha`**。

### 9.3 Release Assets — Links

模型：`Releases::Link`，`enum :link_type`（other / runbook / package / image）。

两种创建方式：

1. 创建 Release 时 nested attributes
2. 独立 API → `Links::CreateService`

Direct Asset Path：`LinkPresenter#direct_asset_url` → `Controller#downloads`。

### 9.4 Release Assets — Sources

**PORO，不存库。** 完整说明见 [§5.2 `Releases::Source` PORO](#52-releasessource-poro)。

要点速查：

- `Releases::Source.all(project, tag)` → 4 种 Workhorse 格式各一个实例
- `Release#sources` 聚合暴露；`assets_count` 计入 sources 数量
- API：`GET /releases` 的 `assets.sources`（`can_read_code?` 时返回）
- Webhook：`release.sources.map(&:hook_attrs)`
- **无 CRUD Service**——与 Links 不同，不能单独「创建/删除」一条 Source

示例 URL：`https://gitlab.example.com/root/app/-/archive/v1.0/app-v1.0.zip`

### 9.5 关联 Milestone

`MilestoneRelease` 关联表，`BaseService#milestones` + `MilestonesFinder` 查找并赋值。

### 9.6 Release Evidence

`Releases::Evidence` 存 JSON 快照。异步链：

```
CreateService → CreateEvidenceWorker → CreateEvidenceService → evidence.save!
```

`EvidencePipelineFinder` 预取 pipeline；`ManageEvidenceWorker` Cron 兜底；`EvidencesController#show` 读取。

Evidence 脱敏（`evidence.rb`）：

```ruby
def summary
  safe_summary.dig('release', 'milestones')&.each { |m| m.delete('issues') }
  safe_summary
end
```

### 9.7 关联 Packages

```ruby
def tagged_packages
  version = tag.sub(/\Av/i, '')
  Packages::Package.for_projects(project_id).displayable.with_version(version)
end
```

### 9.8 Webhook

```ruby
Gitlab::HookData::ReleaseBuilder.new(release).build(action)
# → object_kind: 'release', assets, commit
```

### 9.9 发布事件

`PublishEventWorker` Cron 扫描 upcoming release，发布 `Projects::ReleasePublishedEvent` 到 EventStore。

### 9.10 更新与删除

- **UpdateService**：transaction 内 update + webhook + audit
- **DestroyService**：destroy + webhook + audit + Catalog 联动

---

## 10. DDD 概念映射

| DDD 概念 | GitLab 实现 | Release 示例 |
|----------|-------------|--------------|
| **Entity** | ActiveRecord + namespaced model | `Release`、`Releases::Link` |
| **Value Object** | PORO + Enum | `Releases::Source`、`link_type` |
| **Aggregate Root** | 隐式 AR + 关联约束 | `Release` |
| **Use Case / Application Service** | `app/services/<context>/` | `Releases::CreateService` |
| **Query Object** | `app/finders/` | `ReleasesFinder` |
| **Repository** | ActiveRecord 直接持久化 | `release.save!`（无独立 Repository 类） |
| **Domain Event** | EventStore | `Projects::ReleasePublishedEvent` |
| **Primary Adapter** | Controller / API / GraphQL | `lib/api/releases.rb` |
| **Anti-Corruption Layer** | 参数对象 | `Releases::Links::Params` |
| **Builder (DTO)** | Hook payload | `Gitlab::HookData::ReleaseBuilder` |

**Value Object 特征（`Releases::Source`）**：无 ID、不持久化、运行时构建、封装 URL 计算逻辑。详见 [§5.2](#52-releasessource-poro)。

---

## 11. 权限模型

```ruby
# app/policies/release_policy.rb
rule { protected_tag }.policy do
  prevent :create_release
  prevent :update_release
  prevent :destroy_release
end
```

| 能力 | 使用位置 |
|------|----------|
| `:read_release` | ReleasesFinder、Controller |
| `:create_release` | CreateService、Links::CreateService |
| `:update_release` | UpdateService、Links::UpdateService |
| `:destroy_release` | DestroyService |
| `:read_release_evidence` | EvidencesController |

---

## 12. 架构关系图

```
                    用户 / CI / Release CLI
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
  Controller         REST API          GraphQL     ← 应用层
        │                │                │
        └────────────────┼────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
   *Service           Finder            Worker     ← 领域层
        │                │
        ▼                ▼
   Release + Link + Evidence + Source (PORO)      ← 模型
        │
        ├── Tags::CreateService
        ├── Ci::Pipeline
        └── Projects::ReleasePublishedEvent → EventStore
```

---

## 13. 端到端调用链

### 创建（写）

```
POST /projects/:id/releases  或  GraphQL ReleaseCreate
    → Releases::CreateService#execute
    ├── 权限 + tag 保护
    ├── EvidencePipelineFinder → Ci::Pipeline
    ├── Tags::CreateService（如需）
    ├── Release.save!
    ├── NotificationService + Webhook + CreateEvidenceWorker + Audit
    └──（到达 released_at）PublishEventWorker → EventStore
```

### 列表（读）

```
GET /projects/:id/releases
    → ReleasesFinder#execute
    → Release.preloaded → Serializer → JSON
```

---

## 14. 与 Textbook DDD 的对照

| Textbook DDD | GitLab Releases:: |
|--------------|-------------------|
| Use Case 类 | `Releases::CreateService` 等 Service Object |
| Query Object | `ReleasesFinder` 等 Finder |
| Aggregate Root 显式类 | 隐式：`Release` AR |
| Repository 接口 | ActiveRecord + Finder |
| Primary Adapter | REST / GraphQL / Controller |
| Domain Event | `Projects::ReleasePublishedEvent` + EventStore |
| Bounded Context | `Releases::` namespace |

---

## 15. 关键路径速查

| 类别 | 路径 |
|------|------|
| Bounded Context | `config/bounded_contexts.yml` → `Releases:` |
| 设计指南 | `doc/development/software_design.md` |
| 聚合根 | `app/models/release.rb` |
| 子 Entity | `app/models/releases/`（`link.rb`、`evidence.rb` 等） |
| PORO / Value Object | `app/models/releases/source.rb` |
| **Use Case** | `app/services/releases/` |
| **Git 出站封装** | `lib/gitlab/git/repository.rb` |
| **Gitaly Client** | `lib/gitlab/gitaly_client/` |
| **查询对象** | `app/finders/releases_finder.rb`、`app/finders/releases/` |
| **REST 入口** | `lib/api/releases.rb` |
| **GraphQL 入口** | `app/graphql/mutations/releases/` |
| **Web 入口** | `app/controllers/projects/releases_controller.rb` |
| Workers | `app/workers/releases/` |
| Domain Event | `app/events/projects/release_published_event.rb` |
| Hook Builder | `lib/gitlab/hook_data/release_builder.rb` |
| Policy | `app/policies/release_policy.rb` |
| Schema | `db/docs/releases.yml`、`release_links.yml`、`evidences.yml` |

---

## 16. 阅读建议

1. **先理解分层**：§3 架构总览 → **§5.2 Source PORO** → **§5.5 Model/Service** → **§5.6 Client/Service** → §6 Use Case → §7 Finder → §8 应用层入口。  
   **创建用例专读**：[Release 创建分层](/posts/gitlab-release-create-layering/)
2. **跟踪 CreateService**：从 REST/GraphQL 入口到 Worker 的完整链路（§13）。
3. **对比读/写路径**：列表走 Finder，创建走 Service。
4. **对比 Link 两种入口**：nested attributes vs `Links::CreateService`。
5. **跑 spec**：`spec/services/releases/create_service_spec.rb`。

**延伸阅读**：`WorkItems::Widgets::`（Facet 模式）、`Import::ExportStatus`（策略 + 工厂）。

---

## 附：一句话总结

GitLab 的 **Release** = `Release` 聚合根 + `Link`/`Evidence` Entity。**写操作**由 `app/services/releases/` 的 Use Case 编排；**读操作**由 `app/finders/` 的 Finder 查询；**三种入口**（REST / GraphQL / Controller）只做适配，共享同一套用例与查询逻辑。
