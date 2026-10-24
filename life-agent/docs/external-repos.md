# 外部仓库登记规则

本文规定 `custom\life-agent\` 引入外部仓库时的两种方式、判定阈值与登记格式。
规则一（子模块）与规则二（仅文档）二选一，任何外部仓库都必须先登记再使用。

## 1. 规则一：较小仓库以 git submodule 引入

**判定顺序：先看它是不是 DSH 插件，再看体积。** 若某仓库本身就是一个 DSH 插件（以 `dsh plugin add` 方式安装、落到 profile 目录内、不随本仓库分发），一律按规则二（仅文档）处理，只登记插件名、版本与安装位置，不再重复引入为子模块——同一份上游被子模块和包管理器各拉一次，既重复又会把登记路径写错。规则一只用于「需要随仓库分发源码、且不会通过插件机制安装」的场景；第 3 节的四条阈值在这层判定之后才生效。

较小的外部仓库可以作为 git submodule 加入 `custom\life-agent\` 之下，并在本文「登记台账」与对应条目里写明：

- 仓库完整地址（HTTPS 形式）；
- 用途（在本目录里承担什么）；
- 版本（放进子模块的 commit SHA，以及该 SHA 对应的上游版本号/tag，若有）；
- 本地路径（相对 `custom\life-agent\`）。

约束：

- 子模块内容保持上游原样，不在子模块内长期就地修改；确需修改时先按规则二改判，或在 `custom\life-agent\` 内以覆盖/补丁文件实现。
- 子模块路径统一放在 `custom\life-agent\third-party\<仓库名>\`，不散落到 `skills\`、`mcp\`、`canon\` 等职责目录里。
- 升级子模块只改指向的 commit SHA，并在提交信息里写明旧 SHA → 新 SHA 与升级原因。

## 2. 规则二：过大的仓库只做文档登记

超过阈值的仓库不加入子模块，只在本文记录：

- 完整仓库地址；
- 用途；
- 部署方式（包管理器安装 / 独立目录克隆 / 容器 / 官方安装器）；
- 安装步骤（实际命令由插件阶段回填，本文保留占位）；
- 使用方法（入口、注册方式、启停）；
- 注意事项（许可证、宿主依赖、落盘位置、与 DSH 版本的耦合）。

「仅文档」不等于「不用」：它只是不让仓库内容进入我们的版本库，安装发生在仓库之外。

## 3. 判定阈值

同时满足下列四条才走规则一，任一条不满足则走规则二。

| 维度 | 阈值 | 说明 |
| --- | --- | --- |
| 仓库体积 | `git` 打包后 ≤ 10 MB | 只算仓库自身，不算安装后拉取的依赖与运行时资产 |
| 依赖与落盘体量 | 安装后落盘 ≤ 200 MB，且无系统级依赖 | 系统级依赖指 hypervisor、内核驱动、虚拟化组件、需要 root/管理员常驻的服务、GB 级镜像 |
| 就地修改需求 | 不需要长期就地修改 | 上游可用配置或覆盖文件满足定制；不靠直接改上游源码维持 |
| 分发性 | 许可证允许以源码形式随仓库分发 | MIT/Apache-2.0 等宽松许可可直接纳入；AGPL、GPL 等需单独评估，默认按规则二处理 |

判定只需要回答一个问题：**这个仓库是不是「小、独立、装完就好」的文本型依赖**。是 → 子模块；不是 → 仅文档。

### 3.1 为什么 godot-mcp 在本仓库已经是子模块

现有先例可直接核对：`custom\.gitmodules` 只有一条记录

```
[submodule "MCP/game-engine/godot-mcp"]
	path = MCP/game-engine/godot-mcp
	url = https://github.com/CrimsonSeraph/godot-mcp.git
```

对照阈值（本地实测，`du -sh` 与 `git ls-files | wc -l`）：

| 维度 | 实测值 | 判定 |
| --- | --- | --- |
| 仓库体积 | 约 894 KB，22 个受版本控制的文件 | 远低于 10 MB |
| 依赖与落盘体量 | Node/TypeScript 的 MCP server，依赖随 `npm install` 落在自身目录 | 无系统级依赖 |
| 就地修改需求 | 无需改源码，通过 MCP 配置与启动参数使用 | 满足 |
| 分发性 | 仓库自带 LICENSE | 满足 |

四条全中，因此它是子模块而不是「仅文档」条目。这也说明规则一的门槛不高：真正的 MCP/插件类小仓库通常直接过线。

注意：`godot-mcp` 现有位置是 `custom\MCP\game-engine\godot-mcp`，属于 `custom\` 层的既有约定。
`custom\life-agent\` 作为独立分支的配置区，自己的子模块统一放 `third-party\` 之下，两级路径不互相迁移。

## 4. 条目格式

每个外部仓库一个二级标题，字段固定如下（缺项写「待插件阶段核实」，不要留空）：

```
## <名称>
- 仓库地址：
- 用途：
- 引入方式：子模块 / 仅文档（判定理由一句话）
- 版本：
- 本地路径 / 安装位置：
- 部署方式：
- 安装步骤：占位，插件阶段回填
- 使用方法：
- 注意事项：
```

---

## 5. 条目：dsh-dot

- **仓库地址**：https://github.com/Kevinwu901113/dsh-dot
- **用途**：生活型 Agent 的「常驻与身体」来源——Android 模拟器（`mcp__phone__*` 经 ADB 操控）与 IM 接入（主动联系）由它提供；microVM（其 `computer` 组件）是本阶段不启用的可选加强项，见 [isolation.md](isolation.md)。
- **引入方式**：**仅文档**（规则二）。
- **判定理由**：
  - 仓库体积本身不超标（GitHub API 报 `size` 764 KB，语言 JavaScript/ESM，`package.json` 声明 `0.6.0`、`AGPL-3.0-only`，exports 覆盖 `./computer`、`./phone`、`./qq`、`./interlude` 等多个面）。
  - 但它带来的落盘与依赖面远超仓库体积：核心卖点是自带的 microVM（镜像与 hypervisor 依赖，实际体量待插件阶段核实），属于第 3 节的「系统级依赖 / GB 级镜像」风险项，阈值无法在不安装的前提下证明满足。
  - 本阶段只用到它的 `phone`（模拟器）与 IM 两条通道，microVM 不启用，不需要整包就地。
  - 上游处于高频迭代期（仓库 2026-10-17 创建，默认分支 `main` 最近推送 2026-10-23），把整包固化成语义上「随仓库分发」的子模块，会把一个快速变化、且与我们的用法子集不对齐的 AGPL 工程钉进本仓库。
  - 改判口子：若将来需要随本仓库分发源码（离线部署、需要改上游源码并在仓库内评审），按规则一改判为 `custom\life-agent\third-party\dsh-dot\` 子模块，并同步本条与台账。
- **版本**：登记时上游版本 `0.6.0`（`package.json`）；安装时锁定到具体 commit 并回填 SHA（待插件阶段核实）。
- **本地路径 / 安装位置**：不入仓库。安装目标位置由插件阶段确定（待插件阶段核实）。
- **部署方式**：待插件阶段核实（候选：从上游仓库按官方说明安装/注册为 DSH 插件；若之后发布到 npm 则以包名安装）。
- **安装步骤**：占位。实际命令由插件阶段回填，并要求在执行前把命令、落盘位置、下载体量写入运行记录。
- **使用方法**：
  - 模拟器侧：插件加载后经 `mcp__phone__*` 工具族经 ADB 操控（工具清单待插件阶段核实）。
  - IM 侧：按插件文档完成账号绑定，绑定时只记录账号类型，不记录密码/密钥/令牌（见 [isolation.md 第 4 节](isolation.md)）。
  - microVM：本阶段不启用。
- **注意事项**：
  - 许可证 AGPL-3.0-only：不把其源码纳入本仓库；分发或对外提供服务前需单独评估。
  - microVM 组件与 hypervisor/镜像相关，启用前先按 isolation.md 第 6 节征求用户同意。
  - IM 接入涉及外部消息通道：外发内容必须先问用户（isolation.md 第 6 节第 6 条）。
  - 上游迭代快，安装与升级都要记录版本与来源。

## 6. 条目：dsh-vdesktop

- **仓库地址**：https://github.com/jafewff/dsh-vdesktop
- **用途**：提供用户看不见的 Win32 虚拟桌面执行面——`vdesk_*` 工具族在该桌面内驱动 GUI 程序，用户可在 Web GUI 的 VDesktopPanel 中观看并接管。
- **引入方式**：**仅文档**（规则二），按 DSH 插件安装，不落地到本仓库。
- **判定理由**：
  - 先按第 1 节判定顺序：它是 DSH 插件（`package.json` 里声明了 `dsh.bundle.patch` 与 `dsh.client.platform`，以 `dsh plugin --profile <profile> add github:jafewff/dsh-vdesktop` 安装，pnpm 拉取后落在 profile 目录内），不随本仓库分发，因此走规则二，不再重复引入为子模块。
  - 体积本身不构成障碍：GitHub API 报 `size` 409 KB，`package.json` 声明 `0.2.0`，运行期依赖只有构建用的 `esbuild`；形态是 Node 侧的 `lib/`（打包产物）+ Python sidecar（`sidecar/dshv/`，含 `win32` 子目录），随 DSH 进程启动，不需要 hypervisor 或常驻系统服务。
  - 分发性上无阻碍（仓库自带 MIT LICENSE），但分发与否不是本仓库的判断依据：插件机制已经负责取件与版本记录。
  - 可执行性上也不宜写成子模块：本机 `github.com` 主页当前不通（`api.github.com` 可通），`git submodule add https://github.com/jafewff/dsh-vdesktop` 大概率失败；而插件安装走 pnpm 取件，与子模块是两条路径。
  - 改判口子：若将来需要随本仓库分发源码（离线部署、需要改上游源码并在仓库内评审），按规则一改判为 `custom\life-agent\third-party\dsh-vdesktop\` 子模块，并同步本条与台账。
- **版本**：登记时上游版本 `0.2.0`（`package.json`）；安装后回填 pnpm 锁定的版本与来源（待插件阶段核实）。
- **本地路径 / 安装位置**：profile 目录下（`%USERPROFILE%\.dsh\profiles\<profile>\` 之内，具体子路径待插件阶段回填），不入仓库。
- **部署方式**：以 DSH 插件方式安装——`dsh plugin --profile <profile> add github:jafewff/dsh-vdesktop`，由 pnpm 取件并链接进 profile；不在本仓库检出源码。
- **安装步骤**：占位。插件阶段回填，至少包含：确认目标 profile → 执行 `dsh plugin add` 并记录实际版本/来源 → 确认 `lib/` 已随包提供或按上游 `build` 脚本构建 → 接通 Python sidecar → 冒烟验证 `vdesk_*` 工具可用、VDesktopPanel 可观看与接管。
- **使用方法**：
  - 工具侧：会话中调用 `vdesk_*` 工具族启动程序并操作（实际工具名与参数待插件阶段核实）。
  - 人工侧：在 Web GUI 的 VDesktopPanel 观看画面、用真实鼠标接管；用户要求接管时立即让出控制（isolation.md 第 5 节）。
- **注意事项**：
  - 只在 Windows 宿主上可用；sidecar 是 Python 组件，需与本机 Python 环境匹配（具体版本要求待插件阶段核实）。
  - 与 DSH 版本存在耦合（`.dsh.bundle.patch` / `inject: computerUse, tools`），升级 DSH 后需回归一次。
  - 虚拟桌面里不得存放凭证、不得执行支付类操作；截屏外发前先自查（isolation.md 第 3、4、6 节）。
  - 插件包保持上游原样，不就地改 profile 内的包内容；需要源码级定制时按第 1 节改判为子模块，或改用覆盖文件。

## 7. 登记台账

| 仓库 | 地址 | 方式 | 版本 | 本地路径 | 备注 |
| --- | --- | --- | --- | --- | --- |
| dsh-dot | https://github.com/Kevinwu901113/dsh-dot | 仅文档 | 0.6.0（commit 待回填） | 不入仓库 | AGPL-3.0-only；本阶段只用 phone/IM，microVM 不启用 |
| dsh-vdesktop | https://github.com/jafewff/dsh-vdesktop | 仅文档 | 0.2.0（安装后回填 pnpm 版本） | profile 目录内（`%USERPROFILE%\.dsh\profiles\<profile>\`，待回填），不入仓库 | MIT；DSH 插件形式安装，不重复引入子模块；Windows 专用，含 Python sidecar |
| godot-mcp（既有先例，非本目录） | https://github.com/CrimsonSeraph/godot-mcp | 子模块 | 以 `custom\.gitmodules` 指向的 commit 为准 | `custom\MCP\game-engine\godot-mcp\` | 仅作阈值对照，不在本目录迁移 |

## 8. 变更流程

1. 新仓库先在本文件补条目与台账，写清地址、用途、判定与理由。
2. 判为子模块的，才执行 `git submodule add`（由调度方统一执行 git 操作，子任务不自行提交）。
3. 判为仅文档的，插件阶段安装后回填安装步骤、实际版本与落盘位置。
4. 升级或改判时，改条目而不是新开条目；保留「上次判定 → 本次判定」与原因一句话。

## 9. 待插件阶段核实

- 两个仓库的实际安装命令、依赖版本要求、落盘位置与下载体量。
- dsh-dot 的 microVM 运行时依赖（是否需要 hypervisor、镜像多大）。
- dsh-vdesktop 在 profile 内的实际安装路径、锁定的版本与来源（是否由 pnpm 构建 `lib/`）、Python sidecar 的启动方式。
- 两者与当前 DSH 版本的兼容性（`cordis.patch.yml` 的补丁点是否仍存在）。
