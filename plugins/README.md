# 本地已安装第三方插件清单（custom/plugins）

本目录记录本机在 DSH Web 运行环境中安装的**非上游（第三方）插件**清单及其安装方式，
供重装、迁移、审计参考。快照时间：2026-09-27；上游仓库自带插件（`@deepseek-ai/dsh-*`）不在此列。
数据来自用户 web profile（`%USERPROFILE%\.dsh\profiles\web`），本文不含任何用户私人数据。

---

## 一、当前已安装插件清单

### 1. 顶层安装的插件包

打开 DSH Web → 设置 → Plugins，可以看到以下顶层插件包：

| 包名 | 说明 |
| --- | --- |
| `@linxin666/dsh-web-all` | DSH Web UI 全家桶聚合包：一条命令带入下表全部功能插件 |
| `@linxin666/dsh-i18n` | Web GUI 语言包插件：向 locale catalog 注册俄语（Русский），并集中携带各家族插件命名空间的 ru 词典（缺键通过 SDK 链回退英文） |
| `dsh-better-sidebar` | VSCode 风格右侧边栏（explorer / editor / terminal / git / browser），按会话隔离。对外暴露 service，供其他插件注册侧边栏 tab 与文件查看器 |
| `dsh-context` | 上下文管理插件 |
| `dsh-session-manager` | 会话管理：删除会话需确认、归档管理 |

### 2. `@linxin666/dsh-web-all` 包含的子插件

聚合包内含以下功能插件（全部由 `@linxin666/dsh-web-all` 一键带入）：

| 子包 ID | 组件名 | 说明 |
| --- | --- | --- |
| `@linxin666/dsh-web-all/settings` | web-ui-settings | Web UI 设置分组 |
| `@linxin666/dsh-web-all/plugin-manager` | web-ui-plugin-manager | 插件管理器标签页（npm/git 安装、更新、卸载、冲突回滚） |
| `@linxin666/dsh-web-all/community-plugins` | web-ui-community-plugins | 社区插件索引卡片 |
| `@linxin666/dsh-web-all/market` | web-ui-market | 插件市场 |
| `@linxin666/dsh-web-all/task-board` | web-ui-task-board | 任务看板：Host 权威账本、真实会话执行、Host cron 定时 |
| `@linxin666/dsh-web-all/git-graph` | web-ui-git-graph | Git 图谱与分支选择 |
| `@linxin666/dsh-web-all/remote-web-ui` | web-ui-remote-web-ui | 手机远程控制（扫码配对） |
| `@linxin666/dsh-web-all/pet` | web-ui-pet | 桌面宠物（注册表驱动，可反应于会话状态） |
| `@linxin666/dsh-web-all/ssh` | web-ui-ssh | SSH 远程运维：主机配置/执行/传输/隧道/集群，Web 终端 |
| `@linxin666/dsh-web-all/describe-image` | web-ui-describe-image | `describe_image` 模型工具：让纯文本模型获得图片理解 |
| `@linxin666/dsh-web-all/liangshen` | web-ui-liangshen | 梁神模式 agent preset（两阶段锚定） |
| `@linxin666/dsh-web-all/skill-explorer` | web-ui-skill-explorer | 技能浏览器（按 bundled/project/user/custom/runtime 分组） |
| `@linxin666/dsh-web-all/doctor` | web-ui-doctor | 诊断面板 |
| `@linxin666/dsh-web-all/usage` | web-ui-usage | 用量统计 |
| `@linxin666/dsh-web-all/session-archive` | web-ui-session-archive | 会话归档 |
| `@linxin666/dsh-web-all/model-capabilities` | web-ui-model-capabilities | 模型能力查看 |
| `@linxin666/dsh-web-all/skin-center` | web-ui-skin-center | 皮肤中心（皮肤的唯一载体包） |
| `@linxin666/dsh-web-all/compat` | web-ui-compat | 兼容桥接层（已并入本包 src/client，无需独立 compat npm 包） |

### 3. 可选独立插件（未进全家桶，按需安装）

以下插件不在 `@linxin666/dsh-web-all` 中，如需使用需单独安装：

| 包名 | 说明 | 安装命令 |
| --- | --- | --- |
| `dsh-session-manager` | 会话管理：删除会话需确认、归档管理 | `dsh plugin --profile web add dsh-session-manager` |
| `dsh-context` | 上下文管理插件 | `dsh plugin --profile web add dsh-context` |
| `@linxin666/dsh-i18n` | 语言包（俄语等） | `dsh plugin --profile web add @linxin666/dsh-i18n` |

### 4. 皮肤

| 包名 | 版本 | 说明 | 激活 |
| --- | --- | --- | --- |
| `@linxin666/dsh-client-ui-skin-miku` | 0.2.0 | 初音未来主题：蓝紫品红渐变 + 毛玻璃 + 深浅双主题，纯表现层可完整还原 | `dsh-skin use miku` |

---

## 二、如何安装插件

DSH 插件通过 **profile 机制**安装：每个 profile（如 `web`）在
`%USERPROFILE%\.dsh\profiles\<profile>\` 下维护自己的 `package.json`（声明 `dependencies` 与
`dsh.profile.bundles` 组合列表），重启 `dsh web` 后生效。

### 方式一：官方 CLI（推荐）

`dsh plugin` 子命令把剩余参数转发给 profile 目录里的 pnpm：

```bat
rem 安装（示例：全家桶聚合包）
dsh plugin --profile web add @linxin666/dsh-web-all

rem 安装（示例：独立插件）
dsh plugin --profile web add dsh-better-sidebar
dsh plugin --profile web add dsh-context
dsh plugin --profile web add dsh-session-manager
dsh plugin --profile web add @linxin666/dsh-i18n

rem 指定版本安装
dsh plugin --profile web add @linxin666/dsh-web-all@latest
dsh plugin --profile web add dsh-better-sidebar@0.13.0
```

安装后**重启 `dsh web` 生效**（本机启动器：`custom/launcher/start-dsh.bat`，服务已在运行时会直接打开应用）。

### 方式二：GUI 插件管理器

设置页 → Plugins → **Plugin manager** 标签（由 `@linxin666/dsh-client-ui-plugin-manager` 提供）：

- 从 npm 包名或 git 仓库地址安装，带进度与结果；
- 已安装插件可切换「下次启动启用」、检查更新（npm registry）、更新、卸载；
- 安装冲突可回滚（undo），或交给 agent 修复（repair 会话）；
- 生效开关与安装均在**下次重启时应用**。

### 方式三：手动编辑 profile（进阶）

1. 编辑 `%USERPROFILE%\.dsh\profiles\web\package.json`：
   - 在 `dependencies` 中加入包名与版本；
   - 在 `dsh.profile.bundles` 中加入包名（皮肤类包 `bundleWired: false`，无需加入）；
2. 在 profile 目录执行 `pnpm install`；
3. 重启 `dsh web`。

### 皮肤切换

```bat
dsh-skin use miku
```

皮肤激活互斥，写入 profile 的 `cordis.patch.yml` 托管段（本机 `~/.dsh/cordis.patch.yml` 的
`dsh-skin managed` 段），也可在 GUI 皮肤中心操作。

---

## 三、如何更新插件

### 更新聚合包（推荐方式）

聚合包一次更新即带入全部子插件：

```bat
rem 更新到最新版
dsh plugin --profile web add @linxin666/dsh-web-all@latest

rem 或指定版本
dsh plugin --profile web add @linxin666/dsh-web-all@0.3.0
```

### 更新独立插件

```bat
dsh plugin --profile web add dsh-better-sidebar@latest
dsh plugin --profile web add dsh-session-manager@latest
dsh plugin --profile web add dsh-context@latest
dsh plugin --profile web add @linxin666/dsh-i18n@latest
```

### 更新皮肤

```bat
dsh plugin --profile web add @linxin666/dsh-client-ui-skin-miku@latest
```

### 通过 GUI 更新

设置 → Plugins → Plugin manager → 找到对应插件 → 点击「检查更新」→「更新」。

### 版本查询

```bat
rem 查询 npm 上的最新版本
npm view @linxin666/dsh-web-all version
npm view dsh-better-sidebar version
npm view dsh-context version
npm view dsh-session-manager version

rem 查看本机安装的版本
dsh plugin --profile web list
```

> ⚠️ **升级全家桶后如遇皮肤/面板异常**，先检查 `~/.dsh/cordis.patch.yml` 托管段与 profile 的 `pnpm-lock.yaml`。

---

## 四、如何卸载插件

### 卸载独立插件

```bat
dsh plugin --profile web remove dsh-better-sidebar
dsh plugin --profile web remove dsh-session-manager
dsh plugin --profile web remove dsh-context
dsh plugin --profile web remove @linxin666/dsh-i18n
```

### 卸载聚合包（会同时移除全部子插件）

```bat
dsh plugin --profile web remove @linxin666/dsh-web-all
```

### 卸载皮肤

```bat
dsh plugin --profile web remove @linxin666/dsh-client-ui-skin-miku
```

### 通过 GUI 卸载

设置 → Plugins → Plugin manager → 找到对应插件 → 点击「卸载」。

### ⚠️ 卸载后的清理检查

DSH 插件的卸载有时会出现 **`dependencies` 已移除但 `dsh.profile.bundles` 仍残留** 的情况，导致启动时报：

```
cannot resolve profile bundle "<包名>" from the dsh installation or <profile 路径>
```

如遇此报错，手动编辑 `%USERPROFILE%\.dsh\profiles\web\package.json`：

1. 确认 `dependencies` 中已无该包；
2. 在 `dsh.profile.bundles` 数组中**删除对应条目**；
3. 保存后重启 `dsh web`。

---

## 五、来源仓库

| 仓库 | 说明 |
| --- | --- |
| <https://github.com/zhu1090093659/dsh-web-ui> | dsh-web-ui 插件全家桶（`@linxin666/*`：聚合包、ssh、task-board、liangshen 等） |
| <https://github.com/omdsh-dev/DSH-better-sidebar> | dsh-better-sidebar |
| <https://github.com/hkkz9522/dsh-session-manager> | dsh-session-manager |

---

## 六、本机数据位置（用户数据，不入库）

| 路径 | 内容 |
| --- | --- |
| `%USERPROFILE%\.dsh\profiles\web\package.json` | web profile 的依赖与 bundles 声明（本文档的权威来源） |
| `%USERPROFILE%\.dsh\profiles\web\cordis.patch.yml` | profile 级 patch 层（覆盖官方插件配置） |
| `%USERPROFILE%\.dsh\dsh-ssh.json` | SSH 主机配置（含密码明文，权限 0600，注意保管；可从 `~/.ssh/config` 导入） |
| `%USERPROFILE%\.dsh\task-board\` | 任务看板账本（ledger-v2.json）与调度器状态 |
| `%USERPROFILE%\.dsh\.agent-presets\liangshen\` | 梁神模式 preset 文件（插件升级时自动更新） |
| `%USERPROFILE%\.dsh\cordis.patch.yml` | 皮肤等 patch 层托管段（`dsh-skin managed`） |

---

## 七、注意事项

1. 版本为 2026-09 快照，实际以 `npm view <包名> version` 或 GUI 插件管理器的更新检查为准；
2. 升级全家桶后如遇皮肤/面板异常，先检查 `~/.dsh/cordis.patch.yml` 托管段与 profile 的 `pnpm-lock.yaml`；
3. SSH 密码以明文存放于用户主目录私有文件，传输/执行消耗真实远程资源，操作前先确认；
4. **DSH 依赖用 pnpm 管理，不要用 `npm update`**——npm 的 peer 解析会因 DSH 官方包内部的版本跨度（如 `@deepseek-ai/dsh-settings@0.0.1-rc.1` 要求 `dsh-invariants@^0.0.1-rc.1`，而实际装的是 `0.1.2-rc.1`）而报 `ERESOLVE`，这是正常现象，用 `dsh plugin --profile web update` 即可；
5. `.credentials.yaml` 的 `version` 与 `refs` 字段在新版 DSH 中要求**字符串类型**，手工编辑时注意加引号，且尽量避免手动编辑该文件，优先用 DSH 自身的凭据管理命令。

---

## 八、如何彻底清除环境并重装恢复（保留会话历史）

当 DSH 发生**破坏性变更**（如底层设置 API 重构导致旧插件报 `settings service is absent`），或本地因频繁升级导致依赖树严重污染时，常规的“卸载重装”往往无法根除问题。此时需要**彻底清空 profile 环境并重装**。

**核心原则：删除构建产物与依赖，保留用户数据（会话、凭据、插件持久数据）。**

### 8.1 清理组件清单与保留策略

以下表格记录了用户实际清理和保留的组件。**请务必依照“是否保留”列执行，以防数据丢失**：

| 目标组件 | 所在位置 | 作用 | 是否清理 | 清理后是否丢失会话历史 |
| --- | --- | --- | --- | --- |
| **Profile 插件依赖** | `~/.dsh/profiles/web/node_modules/` | 存放所有已安装的第三方和核心插件 | **✅ 清理** | 否 |
| **Profile 依赖清单** | `~/.dsh/profiles/web/package.json` | 记录插件依赖和 profile 的 bundles 列表 | **✅ 清理** | 否 |
| **Profile 补丁配置** | `~/.dsh/profiles/web/cordis.patch.yml` | 手动添加的插件配置和补丁 | **✅ 清理**（重装后从备份恢复） | 否 |
| **Profile 锁定文件** | `~/.dsh/profiles/web/pnpm-lock.yaml` | 锁定依赖的确切版本 | **✅ 清理** | 否 |
| **Profile 包管理配置** | `~/.dsh/profiles/web/pnpm-workspace.yaml` | pnpm 的安装策略和排除规则 | **✅ 清理**（重装后重建） | 否 |
| **凭据文件** | `~/.dsh/.credentials.yaml` | 存储 API 密钥（明文） | **❌ 保留** | 否 |
| **会话日志** | `~/.dsh/sessions/` | **每次对话的持久化记录** | **❌ 务必保留** | **是，丢失无法恢复** |
| **插件持久数据** | `~/.dsh/storages/` | 插件存放的持久数据（如任务看板、皮肤等） | **❌ 保留** | 可能影响部分插件功能 |

> ⚠️ **高危警告**：绝对不要直接删除整个 `~/.dsh` 目录，否则 `sessions`、`.credentials.yaml` 等核心数据将永久丢失。

### 8.2 标准清理与重装步骤

**第一步：全量备份（安全底线）**
在进行任何清理操作前，先备份整个 `.dsh` 目录到安全位置。

```bat
xcopy /E /I /Y "%USERPROFILE%\.dsh" "%USERPROFILE%\.dsh-backup"
```

**第二步：清理 profile 环境**
进入 `%USERPROFILE%\.dsh\profiles\web` 目录，删除以下内容：

```bat
cd /d "%USERPROFILE%\.dsh\profiles\web"
rmdir /S /Q node_modules
del package.json
del cordis.patch.yml
del pnpm-lock.yaml
del pnpm-workspace.yaml
```

**第三步：初始化并配置策略**
重启 `dsh web`。DSH 会自动重新初始化 profile 目录。
为了应对近期新发布的包被 pnpm 供应链策略拦截（`ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION`），需在 `web` 目录下新建 `.npmrc`，加入排除项：

```ini
minimum-release-age-exclude[]=@linxin666/*
minimum-release-age-exclude[]=dsh-context@0.57.0
minimum-release-age-exclude[]=dsh-session-manager@0.5.3
```

**第四步：重装插件**
重启后，逐步安装插件。**推荐使用 `add` 命令而非 `update`**，以强制重新解析依赖树：

```bat
dsh plugin --profile web add @linxin666/dsh-web-all
dsh plugin --profile web add dsh-better-sidebar
dsh plugin --profile web add dsh-context
dsh plugin --profile web add dsh-session-manager
dsh plugin --profile web add @linxin666/dsh-i18n
```

*注意：如果安装过程中报 `ERR_PNPM_IGNORED_BUILDS`（如 `cloudflared`、`ssh2`、`node-pty` 等原生模块未授权构建），需在 `pnpm-workspace.yaml` 中添加 `allowBuilds` 字段：*

```yaml
allowBuilds:
  cloudflared: true
  cpu-features: true
  ssh2: true
```

**第五步：恢复配置文件与皮肤**
将备份中的 `cordis.patch.yml` 恢复到 `%USERPROFILE%\.dsh\profiles\web\` 下。同时，执行皮肤激活命令：

```bat
dsh-skin use miku
```

**第六步：重启并验证**
重启 `dsh web`，检查：

1. 控制台无红字报错（特别注意 `settings service is absent` 是否复现）。
2. Web 界面能正常加载，深色主题与设定的默认模型生效。
3. 历史会话记录完整保留。
4. 插件管理器中所有插件状态正常。

### 8.3 常见报错速查

| 报错关键字 | 原因 | 解决方法 |
| --- | --- | --- |
| `ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION` | pnpm 拦截发布不足 24 小时的包 | 在 `.npmrc` 中添加 `minimum-release-age-exclude[]=<包名>@<版本>` |
| `ERR_PNPM_IGNORED_BUILDS` | 原生模块未授权运行构建脚本 | 在 `pnpm-workspace.yaml` 中添加 `allowBuilds: { <包名>: true }` |
| `settings service is absent` | 旧插件使用了已废弃的 `settingsScope` API | 彻底清理 `node_modules` 重装；若仍报错，说明插件未适配新版 DSH，需等待作者更新 |
| `cannot resolve profile bundle "<包名>"` | `package.json` 的 `dsh.profile.bundles` 残留了已删除的包 | 手动编辑 `package.json`，删除 `dsh.profile.bundles` 中的对应条目 |
