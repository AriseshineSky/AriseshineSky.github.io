# 10 · 安全与维护

## 信任机制（Project Trust）

04 章讲过机制，这里强调安全视角：

- 信任 = 允许加载项目 `.pi/settings.json`、执行项目扩展、安装项目包 → **项目代码可能让 pi 执行任意命令**
- 三个状态：`ask`（每次询问）/ `always` / `never`；单次 `-a` / `-na`
- 建议：陌生 clone 的项目保持 `ask`；只有你熟悉/信任的项目选 `always`
- 定期检查 `~/.config/pi/agent/trust.json`，清理不再用的项目

## 包与扩展安全

官方明确警告：

> Pi packages run with full system access. Extensions execute arbitrary code. **Review source code before installing third-party packages.**

安装前至少看：
1. 来源（npm 包名、git 仓库与 commit 是否可信）
2. `package.json` 的依赖与 scripts
3. 扩展里是否有可疑的：读密钥/环境变量并外发、`child_process` 执行任意命令、网络请求去向
4. Skills 同理：SKILL.md 可以指示模型执行任何操作，脚本要审

**你的情况**：配置继承自他人，等于「一批未审查的第三方扩展」。抽一个下午逐一读 `extensions/` 源码，不认识的禁用（`pi config` 或移动到备份目录）。

## 沙箱（可选进阶）

如果对执行环境敏感，官方提供容器化方案：`docs/containerization.md`（Gondolin / Docker / OpenShell）。日常个人开发不必上，但跑陌生代码/审查恶意样本时有价值。

## 更新习惯

```bash
pi update --self        # 更新 pi 本体
pi update --all         # pi + 全部包
pi update --models      # 刷新模型目录（新模型出现时）
pi update --extensions  # 只更新包
```

- 更新后用 `/changelog` 看变化
- 安全/关键修复优先更新；`--ignore-scripts` 安装可避免 npm 安装脚本风险（官方安装命令自带）

## 配置备份

你的整体配置约等于一个「可移植的技能包」，值得纳入版本管理：

```bash
cd ~/.config/pi/agent && git init   # 或放进现有 dotfiles 仓库
```

涉及密钥的（`auth.json`、`models-store.json`）**不要提交**，用 `.gitignore` 排除。

## 日常卫生清单

- [ ] `/trust` 项目列表定期清理
- [ ] 新包安装前给它 5 分钟源码审查
- [ ] 季度跑 `pi update --all && pi update --models`
- [ ] 配置目录纳入 git 管理（排除密钥）
- [ ] 关注 `/changelog` 里的安全相关条目