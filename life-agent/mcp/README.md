# mcp/ — 生活型 MCP 清单

本目录只放**生活型 Agent 专用**的 MCP server 定义，不碰 `custom/MCP/` 下的自用工具集。

## 文件

- `mcp.servers.json`：清单源。结构固定为：

```json
{
  "version": 1,
  "note": "说明文字",
  "servers": { "<server 名>": { ... } }
}
```

## 清单是空的时候会发生什么

空清单 `"servers": {}` 是**合法且安全**的状态：合并脚本会报告「没有需要新增的 server」，
不改动任何文件。所以要接入 MCP，必须先把定义写进 `servers`。

## 合并方式

由 `custom/launcher/link-life-mcp.ps1` 负责，把清单里**尚未注册**的 server 追加到目标 profile。
规则是「缺失才补，绝不覆盖同名」——自用已注册的 server（例如 `godot`、`qtcreator`）会被识别并跳过。

```powershell
# 先预演，确认只会补哪些、跳过哪些
.\custom\launcher\link-life-mcp.ps1 -Profile life -DryRun

# 确认无误再真跑（会先备份目标 cordis.patch.yml）
.\custom\launcher\link-life-mcp.ps1 -Profile life
```

判重范围覆盖三处：目标 profile 的 `cordis.yml`、目标 profile 的 `cordis.patch.yml`、
以及 DSH 根级 `~/.dsh/cordis.patch.yml`（本机的 `godot`/`qtcreator` 注册在根级）。

## 字段

每个 server 一个键，键名即 `serverName`。允许的字段：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `transport` | 是 | `stdio` 或 `streamable-http` |
| `command` | stdio 必填 | 可执行文件，例如 `npx`、`node`、`python` |
| `args` | 否 | 字符串数组，不能放对象 |
| `env` | 否 | 字符串键值对 |
| `cwd` | 否 | 子进程工作目录 |
| `url` | http 必填 | `streamable-http` 的地址 |
| `headers` | 否 | http 请求头 |
| `failOnStartupError` | 否 | 启动失败是否中断 |
| `id` / `disabled` | 否 | 条目 id 与禁用开关 |

约束：

- `stdio` 与 `url`/`headers` 互斥；`streamable-http` 与 `command`/`args`/`env`/`cwd` 互斥。
- 键名必须与 `serverName` 一致（若显式写了 `serverName`）。
- 出现上表以外的字段会直接报错，不会静默忽略。

## 三个可照抄的模板

**本地 stdio（npx 拉包）**

```json
{
  "transport": "stdio",
  "command": "npx",
  "args": ["-y", "<包名>", "<参数>"],
  "env": {}
}
```

**本地 stdio（自己指定脚本与工作目录）**

```json
{
  "transport": "stdio",
  "command": "node",
  "args": ["<脚本绝对路径>"],
  "cwd": "<工作目录>",
  "env": { "SOME_PATH": "<值>" }
}
```

**远程 streamable-http**

```json
{
  "transport": "streamable-http",
  "url": "http://127.0.0.1:<端口>/",
  "headers": {}
}
```

## 注意

- **不要在这里写密码、令牌、API key**。需要凭据的 server 用 `env` 指向环境变量，由 DSH 的凭证机制提供，
  不要把它们写进本文件——本文件是入库的。
- 生活型 Agent 的两个「身体」（虚拟桌面、Android 手机）是**插件**，不是 MCP，不需要在本文件登记。
  这里只登记额外想要的外部工具。
- 改完清单要重跑上面的合并命令才会生效；DSH 需要重启才能加载新注册的 server。
