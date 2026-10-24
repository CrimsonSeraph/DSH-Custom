# 生活型 Agent 独立区（life-agent）

本目录是「生活型」Agent 的独立配置区：人设、幕间行为、IM 主动联系、生活型 skill 与 MCP 清单都在这里，
与用户自用的 skill / MCP / tools / 快捷启动配置严格区分，互不覆盖。
DSH 不替用户决定性格，人设由用户填充。

## 边界规则

1. `custom\` 下已有的自用 skill、MCP、快捷启动配置不得修改；只有为「追加引用」做非破坏性编辑时才可以动，且必须保留原有内容。
2. 生活型 skill 只放 `life-agent\skills\`，生活型 MCP 只放 `life-agent\mcp\`，不写入自用目录。
3. 快捷启动脚本采用「追加联接步骤」的方式：新增生活型联接，原有自用联接保持不变。
4. 模型文件位于 `G:\LocalAI`，不复制进仓库、不纳入版本控制。
5. 本目录只放文本资产（人设、prompt、清单、文档）；二进制、密钥、令牌、凭证一律不入库。

## 子目录职责

| 目录 | 职责 |
| --- | --- |
| `README.md` | 本说明：边界规则、目录职责、自用与生活型的对照、提交记录 |
| `canon\` | 权威文本：人设模板（persona.md）等长期有效的定义 |
| `prompts\` | 行为 prompt 模板：幕间生活（interlude.md）、IM 主动联系（im-contact.md） |
| `skills\` | 生活型专用 skill，仅在生活型会话中加载 |
| `mcp\` | 生活型 MCP server 清单源（mcp.servers.json），合并时只补缺失项 |
| `local-model\` | 本地模型相关配置与说明；模型权重本体在 `G:\LocalAI`，不在此目录 |
| `docs\` | 设计说明、运行记录与后续阶段文档 |

## 自用 vs 生活型专用

| 维度 | 自用（`custom\` 既有目录） | 生活型专用（本目录） |
| --- | --- | --- |
| skill | `custom\skills\`，面向开发与日常工具 | `life-agent\skills\`，面向生活场景 |
| MCP | `custom\MCP\` 中的既有 server 定义 | `life-agent\mcp\mcp.servers.json`，同名时不覆盖自用定义 |
| 快捷启动 | `custom\launcher\` 中的既有联接 | 以追加联接步骤接入，不改动原有联接 |
| 人设与行为 | 无（使用默认角色） | 由 `canon\` 与 `prompts\` 定义，内容由用户填写 |
| 模型文件 | 不涉及 | 引用 `G:\LocalAI`，不入库 |

## 待办边界

以下内容不在本目录的当前阶段范围内，由其他子任务负责，本目录不预先占用其实现：

- `local-model\` 与 `docs\` 的具体内容。
- 快捷启动脚本的追加联接实现。

## 提交记录

| 提交 | 说明 |
| --- | --- |
| `09a64eb` | feat(life-agent): 创建生活型 Agent 目录骨架与人设模板 |
| `a4c3656` | docs(life-agent): 补全隔离边界与外部仓库登记文档 |
| `0ff3edc` | chore(scripts): 启动脚本追加生活型 skill 与 MCP 联接 |
| `e02828c` | chore(local-model): 落地本地 Qwen3.5-9B 启动脚本与实测调优记录 |
