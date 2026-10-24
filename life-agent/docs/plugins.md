# life profile 插件安装登记

本文件记录「身体」插件（dsh-dot、dsh-vdesktop）在本地 DSH 环境中的安装与登记结果。
本阶段只完成**安装与登记**，不含任何运行时验证，详细边界见第 11 节。

## 1. 本阶段范围与结论

- 目标 profile：`life`（`C:\Users\LTYY\.dsh\profiles\life`），与任务书 §4.1 的 `desktop` 不同，原因见第 2 节。
- 已装好三个包：`dsh-dot@0.6.0`、`dsh-vdesktop@0.2.0`、`@xmanrui/dsh-im@5.4.0`。
- `dsh --profile life --dump-config` 退出码 0、stderr 为空，五个 bundle 层全部参与组装。
- 未创建 AVD，未执行 `/phone accept`，未验证 VDesktopPanel，未接模型端点。

## 2. 为什么 profile 名是 life 而不是任务书里的 desktop

任务书 §4.1 要求 `dsh plugin --profile desktop add ...`。该命令在本机 dsh 0.2.1-rc.2 上**无法执行**，
`desktop` 是产品为 Electron 应用保留的 profile 名。四条证据：

1. CLI 原文字面拒绝。实测命令与输出（exit 0，错误走 stderr）：

   ```
   $ dsh plugin --profile desktop add github:Kevinwu901113/dsh-dot @xmanrui/dsh-im
   error: profile "desktop" is managed exclusively by the Electron application
   ```

2. 拒绝点定位在 `C:\Users\LTYY\AppData\Local\pnpm\global\v11\d1cc-1a13c1f5573\node_modules\@deepseek-ai\dsh\lib\bin.js`：
   第 35-37 行的 `rejectElectronProfile()` 对 `profile.toLowerCase() === "desktop"` 直接 `program.error`；
   第 112 行（boot 路径）无条件调用它，第 119 行（plugin 路径）只有 `manageDesktopProfile` 为 true 时放行。
   `manageDesktopProfile` 是 `runCli(options)` 的编程参数（同文件第 209 行），只由 Electron 载体进程传入，
   CLI 侧没有任何 flag 或环境变量能把它打开。

3. 同包 `lib/plugin-BiveYA7h.js` 的 `requireDesktopProfile()` 要求该 profile 先由应用初始化，错误原文：
   `Open DeepSeek Harness Desktop once to initialize its profile, then fully quit it before running dsh plugin --profile desktop.`

4. `@deepseek-ai/dsh-app-boot` 的 `PROFILE_TEMPLATES`（`lib/index.js:551-561`）只含
   `acp`、`web`、`headless`、`sdk`、`sdk-minimal`，没有 `desktop`。且本机未安装 DSH Desktop 应用
   （`Program Files` 与 `%LOCALAPPDATA%\Programs` 下均无），`~/.dsh/profiles` 原先只有 `tui`、`web`。

因此即使手工造出 `profiles/desktop`，`dsh --profile desktop` 仍被第 112 行永久拒绝，只能由 Electron 载体启动，
拿到的是一份跑不起来的 body。改用 `life` 是既能隔离又真正可启动的路径，启动方式为 `dsh life`。

**改判口子**：若将来安装了 DSH Desktop 应用，可由该应用启动一次以初始化 `profiles/desktop`，
再由它为 desktop profile 装同样的插件；届时本文第 3 节的命令把 `life` 换成 `desktop` 即可，
但 CLI 直装路径仍然不可用。

## 3. 安装记录：命令原文与真实输出

所有命令在 `F:\Projects\deepseek-harness` 之外的工作目录执行不影响结果，profile 由 CLI 解析到 `~/.dsh/profiles/life`。

### 3.1 安装 dsh-dot 与 dsh-im

```
dsh plugin --profile life add github:Kevinwu901113/dsh-dot @xmanrui/dsh-im
```

该次调用在命令行前台超过 5 分钟仍未结束（首次解析 + 下载 223 个包），前台 shell 被超时中断；
中断时 `package.json`、`pnpm-lock.yaml` 已写出、`node_modules` 已开始硬链接。
随后由第 3.2 节的 `pnpm add` 完成补齐。

### 3.2 安装 dsh-vdesktop

```
dsh plugin --profile life add github:jafewff/dsh-vdesktop
```

真实输出要点：

```
Packages: +223
Progress: resolved 287, reused 219, downloaded 4, added 223, done

dependencies:
+ @xmanrui/dsh-im 5.4.0
+ dsh-dot 0.6.0
+ dsh-vdesktop 0.2.0

[ERR_PNPM_IGNORED_BUILDS] Ignored build scripts: esbuild@0.23.1
dsh: plugin command failed; diagnostics: C:\Users\LTYY\.dsh\profiles\life\.plugin-manager\logs\operation-exW5Wo\pnpm.log
```

三个包全部安装成功。CLI 因 `ERR_PNPM_IGNORED_BUILDS` 返回非零，但该警告不影响本用途：
`esbuild@0.23.1` 是 dsh-vdesktop 的依赖，只在其 `build` 脚本（`scripts/build-ts.mjs`）里用到；
实测 `node_modules/dsh-vdesktop/lib/index.js` 与 `lib/client.js` 对 `esbuild` 的引用次数均为 **0**，
运行期不加载它，因此没有执行 `pnpm approve-builds`。

两个 git 依赖均由 pnpm 从 codeload 解析，**没有**触发 `prepare` 构建（dsh-dot 没有 `prepare` 脚本；
dsh-vdesktop 的 `lib/` 随仓库提交）。

### 3.3 组装修正

`package.json` 的 `dsh.profile.bundles` 由 `["@deepseek-ai/dsh-base"]` 就地补全为第 4 节的五条。
bundle 改动只动元数据，不涉及依赖，未重新执行 install。

同一目录下的 `cordis.patch.yml`（profile 级 patch 层）同时写入了一条 `vdesktop` 的 `sidecarCwd` 覆盖，见第 7 节。

组装校验（短命令，退出即返回，不启动长驻会话）：

```
dsh --profile life --dump-config
```

退出码 0，stderr 为空，输出 47939 字节、34 个层头，五个 bundle 层头齐全：
`# == @deepseek-ai/dsh-base`、`# == @deepseek-ai/dsh-web-app`、`# == dsh-dot`、`# == @xmanrui/dsh-im`、`# == dsh-vdesktop`。

## 4. life profile 的 package.json 全文

`C:\Users\LTYY\.dsh\profiles\life\package.json`：

```json
{
  "name": "dsh-profile-life",
  "private": true,
  "dependencies": {
    "@xmanrui/dsh-im": "^5.4.0",
    "dsh-dot": "git+https://github.com/Kevinwu901113/dsh-dot.git",
    "dsh-vdesktop": "git+https://github.com/jafewff/dsh-vdesktop.git"
  },
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "@deepseek-ai/dsh-web-app",
        "dsh-dot",
        "@xmanrui/dsh-im",
        "dsh-vdesktop"
      ]
    }
  }
}
```

`@deepseek-ai/dsh-base` 与 `@deepseek-ai/dsh-web-app` 不在 `dependencies` 里，与现有 `web` profile 一致，
由 dsh 安装自身解析（实测存在于
`...\node_modules\@deepseek-ai\dsh\node_modules\@deepseek-ai\dsh-web-app`）。
保留 `@deepseek-ai/dsh-web-app` 是为了能在 Web GUI 里打开 VDesktopPanel 的 `shell.overlay`。

## 5. 依赖核对：pnpm ls

```
$ dsh plugin --profile life list --depth=0
dsh-profile-life C:\Users\LTYY\.dsh\profiles\life (PRIVATE)
│   dependencies:
├── @xmanrui/dsh-im@5.4.0
├── dsh-dot@0.6.0
└── dsh-vdesktop@0.2.0

3 packages
```

实际来源（`pnpm-lock.yaml` 解析出的 commit）：

| 包 | 版本 | 来源 | commit |
| --- | --- | --- | --- |
| dsh-dot | 0.6.0 | github:Kevinwu901113/dsh-dot | `95676238f104c54419c5d6bf2c3e6c6ea34e9d74` |
| dsh-vdesktop | 0.2.0 | github:jafewff/dsh-vdesktop | `5ea4840908d5be289d7dc8cf171906f1bf9aa0f5` |
| @xmanrui/dsh-im | 5.4.0 | npm registry | 按 semver `^5.4.0` 解析 |

三者均为 floating 引用（分支头 / semver range），重装可能前移；需要钉死时把这两个 `git+https` 换成带 `#<commit>` 的形式。

## 6. dsh-dot：来源、版本、bundle 名与能力分组

- 来源仓库：`https://github.com/Kevinwu901113/dsh-dot`，许可证 AGPL-3.0-only。
- 安装到的实际版本：`0.6.0`（commit 见第 5 节）。
- **声明的 bundle 名**：`dsh-dot`。出处 `node_modules/dsh-dot/package.json` 的 `dsh.bundle.patch` 字段，
  值为 `"./cordis.patch.yml"`；bundle 在 profile 里的名字就是用包名 `dsh-dot`。
- 包内入口由 `package.json` 的 `exports` 决定，能力分组的对应关系：

| 能力分组 | 包内入口（exports 键） | 实际文件 | 贡献的插件条目 id | 暴露给模型的工具 |
| --- | --- | --- | --- | --- |
| computer | `dsh-dot/computer` | `src/computer/vm.js` | `dot-computer`、`dot-subprocess`、`dot-gate`、`dot-mcp`、`dot-ui` | `mcp__vm__*` |
| phone | `dsh-dot/phone` | `src/phone/phone.js` | `dot-phone` | `mcp__phone__*` |
| interlude | `dsh-dot/interlude` | `src/interlude/core.js` | `dot-interlude` | 幕间（Canon、连续性、主动联络） |
| IM | `dsh-dot/dot` | `src/dot/core.js` | `dot` | 定时运行 → IM、静默协议、审批卡片 |

两点需要说明，避免以后误读上表：

1. dsh-dot 自己把「IM」这一组叫 `dot`（always-on glue，条目 id `dot`），它本身不发消息，IM 通道来自
   外部依赖 `@xmanrui/dsh-im`。表里按任务书的分组习惯把二者对齐。
2. dsh-dot 还有第五组 **qq**（`dsh-dot/qq` → `src/qq/qq.js`，条目 id `dot-qq`），
   在 VM 里跑 NapCat/OneBot 11，依赖 computer 分组。任务书未列，此处补记以免遗漏。

各组都可用环境变量关闭：`DSH_DOT_COMPUTER=off`、`DSH_DOT_PHONE=off`、`DSH_DOT_QQ=off`，
关闭后对应条目 `disabled: true`。另有 `DSH_DOT_HOME`、`DSH_INTERLUDE_HOME` 指定角色工作目录。

## 7. dsh-vdesktop：vdesk_* 工具、VDesktopPanel、Python sidecar

- 来源仓库：`https://github.com/jafewff/dsh-vdesktop`，`private: true`（未发布到 npm，只能从 git 装）。
- 安装到的实际版本：`0.2.0`（commit 见第 5 节）。
- **声明的 bundle 名**：`dsh-vdesktop`。出处 `node_modules/dsh-vdesktop/package.json` 的 `dsh.bundle.patch`
  字段，值为 `"./cordis.patch.yml"`；条目 id 为 `vdesktop`。

**vdesk_* 工具来自哪个包**：全部来自 `dsh-vdesktop` 包自身的 `lib/index.js`（`main` 指向该文件），
不是外部 MCP server。在该文件里能查到的工具名共 12 个：
`vdesk_click`、`vdesk_keyboard`、`vdesk_mouse`、`vdesk_type`、`vdesk_screenshot`、`vdesk_zoom`、
`vdesk_read_text`、`vdesk_save_file`、`vdesk_desktop_create`、`vdesk_desktop_list`、
`vdesk_desktop_close`、`vdesk_orphan_sweep`。

**VDesktopPanel 的入口**：
- 组件实现：`node_modules/dsh-vdesktop/lib/client.js` 内的 `VDesktopPanel` 类
  （源码位置 `src/client/VDesktopPanel.ts`，构建产物 45542 字节）。
- 客户端注册：同一文件里 `ctx.slots.register({ name: "shell.overlay", id: "dsh-vdesktop", locale: "vdesktop" }, ...)`，
  即挂到 `shell.overlay` 插槽，靠 `package.json` 的 `dsh.client.platform = "web"` 加载，
  依赖 `dsh.inject = ["computerUse", "tools"]`。
- 因此它必须跑在 **Web GUI / 桌面 GUI** 里才有界面，TUI profile 里看不到。

**Python sidecar 位置**：
- 随包目录：`node_modules/dsh-vdesktop/sidecar/`，Python 包名为 `dshv`
  （`sidecar/dshv/`、`sidecar/pyproject.toml`，`requires-python >=3.11`，**无第三方依赖**，纯 ctypes）。
- 启动方式：`python -m dshv --rpc stdio`，由 `lib/index.js` 以 `cwd: c.sidecarCwd` 拉起子进程。
- **`sidecarCwd` 上游硬编码，已在 profile 层覆盖。** 随包 `cordis.patch.yml` 第 7 行把 `sidecarCwd`
  硬编码成作者机器上的 `D:\Project\dsh-virtaul-computer\sidecar`（编译产物 `lib/index.js` 里甚至退化成
  `D:Projectdsh-virtaul-computersidecar`），本机不存在该路径，sidecar 起不来、`vdesk_*` 全部不可用。

  已在 `C:\Users\LTYY\.dsh\profiles\life\cordis.patch.yml` 里按条目 id `vdesktop` 覆盖为本机路径：

  ```yaml
  # profile-layer patch replaces the whole config object, so restate every key the bundle set.
  - id: vdesktop
    config:
      sidecarPath: python
      sidecarArgs: ['-m', 'dshv', '--rpc', 'stdio']
      sidecarCwd: 'C:\Users\LTYY\.dsh\profiles\life\node_modules\dsh-vdesktop\sidecar'
      callTimeoutMs: 60000
  ```

  两个要点，改这条时会踩：

  1. **profile 的 patch 层是整体替换 `config` 对象，不是逐键合并。** 起初只写了 `sidecarCwd` 一条，
     `dsh --profile life --dump-config` 里 vdesktop 的 `config` 就只剩下 `sidecarCwd`，
     `sidecarPath`、`sidecarArgs`、`callTimeoutMs` 全部消失（等于没了启动命令和参数）。
     所以覆盖时必须把上游 `config` 的其余键一并重述。补齐后 `dump-config` 里四个键齐全。
  2. **重装或升级 `dsh-vdesktop` 后需复核该覆盖是否仍指向正确目录**，且上游若新增 `config` 键，
     这条覆盖不会自动带上，必须手动补。

  覆盖生效的实证：`dsh --profile life --dump-config` 中该层显示为
  `# == dsh-vdesktop, patched by C:\Users\LTYY\.dsh\profiles\life\cordis.patch.yml`，
  其 `sidecarCwd` 值为本机路径，退出码 0、stderr 为空。
  本机 `python` 可用，版本 3.13.9（`requires-python >=3.11`，无第三方依赖）。

## 8. Android 模拟器（AVD）

- **当前状态：未创建。** 待 `/phone accept` 后生成。
- 依据：`dsh-dot` 的 phone 组件在首次启动时才从 Google 仓库下载 emulator、platform-tools 和一个系统镜像
  （约 2 GB），并且必须先接受 Android SDK 许可。
- 生成后的位置与标识（来自 `node_modules/dsh-dot/src/phone/phone.js` 与包内 `README.md`）：
  - AVD 根目录：`~/.dsh/phone/`
  - AVD 具体路径：`~/.dsh/phone/avd/dot.avd/`
  - AVD 名：`dot`（`docs/phone.md` 与 `phone.js` 的默认 `avd: 'dot'`）
  - 控制台端口 5554，adb 序列号 `emulator-5554`
  - 安装日志：`~/.dsh/dsh-phone.log`；审计：`~/.dsh/dsh-phone-audit.jsonl`；设置：`~/.dsh/dsh-phone.json`
- 实测 `~/.dsh/phone` 目前不存在；`~/.android/avd` 存在但为空目录（与 dsh-dot 无关，它不用 avdmanager，也不写这里）。
- 前提：Windows 需要 WHPX 硬件虚拟化。
- 关闭方式：`DSH_DOT_PHONE=off`。

## 9. IM 绑定（只登记账号类型）

本文件**只记录账号类型，不记录任何账号本身或凭证**。请用户自行补全下表的空位。

| 通道 | 账号类型 | 账号标识（用户填） | 绑定状态（用户填） |
| --- | --- | --- | --- |
| IM 主通道（`@xmanrui/dsh-im`） | 待填：例如「某平台个人账号」 | | 未绑定 |
| QQ（`dsh-dot/qq`，VM 内 NapCat） | 待填：例如「某平台个人账号」 | | 未绑定 |

对应的绑定入口（重启后再做，本阶段未执行）：

- QQ：在 dsh 里 `/qq install` → `/qq account <号码>` → `/qq qr` 扫码登录。
  账号也可由 `DSH_DOT_QQ_ACCOUNT` 提供，二维码属凭证，不落盘到本文件。
- IM 通道的账号配置在 `@xmanrui/dsh-im` 的设置页里完成。

## 10. 待用户确认项

以下三项都要等用户重启 DSH 之后才会触发，属于「要不要现在付这个代价」的决定：

1. **`/phone accept` 的约 2 GB 下载。** 接受 Android SDK 许可后，phone 组件才从 Google 仓库拉
   emulator、platform-tools 和一个系统镜像（约 2 GB），然后建 AVD、开机。不执行就没有手机。
   详见第 8 节。
2. **computer 分组首次启动会拉 microVM 镜像。** microsandbox 的 npm 包本身只有 738 KB 且**没有
   install/postinstall 脚本**，安装期不下载任何镜像；镜像是在 VM 首次启动时拉取的
   （包内注释：`The first boot may spend minutes pulling the image`）。首次启动会等较久。
3. **IM 与 QQ 的账号绑定。** 账号类型与标识需用户自己填（第 9 节留了空位）。
   QQ 走 `/qq install` → `/qq account <号码>` → `/qq qr`，二维码属凭证，不落盘到本文件。

已在本次任务中解决、不再待确认的两项，记在此处备查：

- `@xmanrui/dsh-im` 已作为第 4 个 bundle 加入 `dsh.profile.bundles`（位置在 `dsh-dot` 之后），
  `dump-config` 里能查到 `# == @xmanrui/dsh-im` 层头与条目 `xmanrui-dsh-im`。
  该包的 `dsh.compatibility.profiles` 只列了 `["web"]`，但加入 `life` 后
  `dump-config` 与 `dsh plugin --profile life version-exemptions` 均无任何兼容性提示（stderr 为空、返回 `{}`）。
- vdesktop 的 `sidecarCwd` 已在 profile 层覆盖为本机路径（第 7 节）。
  `esbuild@0.23.1` 的构建脚本被 pnpm 忽略（第 3.2 节），实测运行期代码对该包引用次数为 0，无影响。

## 11. 本阶段未做的事

本阶段只完成**安装与登记**。以下三项明确**未执行**，都要等用户重启 DSH 之后再做：

- **未执行 `/phone accept`** —— 因此没有下载 Android SDK 大件、没有创建 AVD、没有启动模拟器。
- **未验证 VDesktopPanel** —— 没有启动带 Web GUI 的会话，`shell.overlay` 插槽没有实际渲染过，
  sidecar 没有拉起过，`vdesk_*` 没有实际调用过。
- **未接模型端点** —— 没有配置任何 LLM provider / API endpoint，没有发起模型请求。

另外未做：未运行 `life` profile 的常驻会话、未执行 `custom/life-agent/mcp/mcp.servers.json` 的合并脚本
（真实合并留到重启之后的阶段）。

## 12. 只读自证（md5 前后一致）

以下文件在安装前后 md5 完全相同，证明 `tui`、`web` profile 与根级 patch 未被改动
（用 Node 的 `crypto.createHash('md5')` 计算，环境无 `md5sum`）：

| 文件 | 安装前 md5 | 安装后 md5 |
| --- | --- | --- |
| `~/.dsh/profiles/tui/package.json` | `6ed19d9efcf5f5951f15b218278732c9` | `6ed19d9efcf5f5951f15b218278732c9` |
| `~/.dsh/profiles/tui/pnpm-lock.yaml` | `f313fea39a32b9900fe833e5b2ef5b40` | `f313fea39a32b9900fe833e5b2ef5b40` |
| `~/.dsh/profiles/tui/cordis.yml` | `da08f43320f829ed34ec07c00c4f31e5` | `da08f43320f829ed34ec07c00c4f31e5` |
| `~/.dsh/profiles/web/package.json` | `2c536f17ead38e3908e4159824aa2af3` | `2c536f17ead38e3908e4159824aa2af3` |
| `~/.dsh/profiles/web/pnpm-lock.yaml` | `f8d8964e207ea218575deea298a95e7d` | `f8d8964e207ea218575deea298a95e7d` |
| `~/.dsh/profiles/web/cordis.yml` | `da08f43320f829ed34ec07c00c4f31e5` | `da08f43320f829ed34ec07c00c4f31e5` |
| `~/.dsh/cordis.patch.yml` | `9aa69ff8536916a3d0db756d0dfaab2d` | `9aa69ff8536916a3d0db756d0dfaab2d` |

`~/.dsh/settings.yaml` 在本次任务前后都不存在，未创建也未改动。
