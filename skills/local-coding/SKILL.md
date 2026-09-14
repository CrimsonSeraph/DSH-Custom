---
name: local-coding
description: 编程任务优先走本地 LM Studio 代码模型（默认 Qwen2.5-Coder-14B），仅当用户明确"不限时长"时才用 Qwen3-Coder-30B；复杂决策、跨文件重构、架构设计仍交主模型
whenToUse: 写代码、解释代码、审查代码、生成测试/样板、格式化转换、正则/SQL 生成
---

# 本地编程（Local Coding）

编码任务按"有界 / 复杂"分流：**有界任务走本地代码模型**（省 token、离线可用），
**复杂决策留主模型**（跨文件重构、架构设计、疑难 bug）。

本地代码模型**不消耗主模型 token、不计费**。同样一段代码审查任务走本地 = 主模型 0 token。

## 分工原则

| 任务类型                                                            | 走哪里      | 模型              |
| ------------------------------------------------------------------- | ----------- | ----------------- |
| 单文件解释 / 代码审查 / 生成测试 / 样板代码 / 正则 / SQL / 格式转换 | 本地        | Qwen2.5-Coder-14B |
| 模糊请求 / 复杂 bug / 跨文件重构 / 架构设计 / 性能优化 / 安全审计   | 主模型(DSH) | —                 |
| "不限时长"任务（用户显式声明）                                      | 本地        | Qwen3-Coder-30B   |

**判断依据**：

- 只看少量文件、或答案可以一眼验证 → 本地
- 需要看 3+ 个文件、或需要设计决策 → 主模型
- 用户说"慢慢来 / 不赶时间 / 尽量好 / 不限时长" → 本地 Qwen3-Coder-30B

## 模型

| 别名（`model` 字段）                       | 实际模型                   | 大小 / 量化    | 场景                                                         |
| ------------------------------------------ | -------------------------- | -------------- | ------------------------------------------------------------ |
| `coder` / `code` / `default-coder`         | qwen2.5-coder-14b-instruct | ~9GB / Q4_K_M  | **常态默认**：可完整加载到 12GB 显存，速度 ~20-30 tok/s      |
| `coder-deep` / `coder-long` / `deep-coder` | qwen3-coder-30b            | ~18GB / Q4_K_M | 需要 CPU Offload，速度 ~9-22 tok/s，质量更高，仅用户声明时用 |

**一次只加载一个模型**（显存限制）。同一轮任务固定用一个模型——切换一次 7-10 秒。

**重要**：切换到本地代码模型会卸载当前视觉模型，反之亦然。不要在同一轮任务里交叉使用编码和识图。

## 如何使用

两个端点都是 OpenAI 兼容：

```bash
ROUTER=${LMSTUDIO_ROUTER_BASE:-http://127.0.0.1:1235}
TOOLS=${LMSTUDIO_TOOLS:-<仓库根>/custom/tools/LMStudio}

# 默认（Qwen2.5-Coder-14B）
curl -s -m 300 "$ROUTER/v1/chat/completions" -H 'Content-Type: application/json' -d '{
  "model": "coder",
  "messages": [{"role":"user","content":"解释 src/auth.ts 第 100-150 行"}],
  "max_tokens": 1024, "temperature": 0.2
}'

# 深度模式（Qwen3-Coder-30B），仅在用户声明不限时长时
curl -s -m 600 "$ROUTER/v1/chat/completions" -H 'Content-Type: application/json' -d '{
  "model": "coder-deep",
  "messages": [{"role":"user","content":"..."}],
  "max_tokens": 4096
}'
```

显式加载 / 卸载：

```bash
python "$TOOLS/lmstudio_router.py" load coder           # 加载 14B
python "$TOOLS/lmstudio_router.py" load coder-deep      # 加载 30B（慢）
python "$TOOLS/lmstudio_router.py" unload --all         # 释放显存
```

## 上下文控制（关键）

本地模型显存有限（12GB），**不要整项目塞进去**。喂之前先裁剪：

1. **只给相关文件**：只给当前任务相关的那几个文件 + 相关类型定义
2. **截断文件内容**：只给相关函数或类，不要整文件
3. **不要带完整日志**：日志/编译输出先 `head -c 4000` 或提炼成要点
4. **不要带历史对话**：一轮独立任务用一个新会话
5. **理想上下文**：16K 以下。12GB 显存下 16K 是舒适上限

**这一层裁剪由主模型负责**——不要让 DSH 发原始上下文给本地模型。

## 降级逻辑

本地链路不通时按顺序自愈：

1. **探测**：`curl -s -m 3 "$ROUTER/health"`
2. **router 没起来 → 先启动**：
   ```bash
   cd <仓库根>/custom/tools/LMStudio
   PYTHONIOENCODING=utf-8 nohup python lmstudio_router.py serve > /tmp/lmstudio-router.log 2>&1 &
   sleep 6 && curl -s -m 5 "$ROUTER/health"
   ```
3. **模型没加载 → 加载**：`python "$TOOLS/lmstudio_router.py" load coder`
4. **本地全部失败 → 主模型兜底**：直接自己处理，并告知用户"本地代码模型不可用"
5. **不要在没有用户同意时**把任务转给外部 API

## 故障排查

| 现象                      | 处理                                                     |
| ------------------------- | -------------------------------------------------------- |
| `curl` 连不上 1235        | router 没起来，按降级第 2 步启动                         |
| 请求成功但 `content` 空串 | 换 `coder-deep` 重试，或换视觉模型确认不是 router 问题   |
| 首个请求特别慢（7-10s+）  | 正常：正在切换模型                                       |
| 速度很慢（< 10 tok/s）    | 可能在用 `coder-deep`（CPU offload）。切回 `coder` 即可  |
| 显存吃紧                  | `python "$TOOLS/lmstudio_router.py" unload --all`        |
| 同时需要视觉任务          | 不要同轮混用。先做完编码任务再切视觉；或先做视觉再切编码 |

## 成本说明

- 本地推理**不计费、不消耗主模型上下文**
- 对比：一次中等规模代码审查，走主模型需要读 5000-20000 token 的源文件；走本地，主模型只需发送 250 token 的指令 + 接收 500 token 摘要
- 估算：有界任务转本地可以节省主模型 **80-95%** 的 token

## 不要做的事

- ❌ 把整个项目塞给本地模型（显存扛不住，上下文会溢出）
- ❌ 让本地模型做架构设计、跨文件重构（做不好，反而浪费你的审查时间）
- ❌ 在同一轮任务里混用 coder 和 vision（每次切换 7-10 秒）
- ❌ 用户没说"不限时长"就用 `coder-deep`（速度慢，影响体验）
- ❌ 让本地模型直接对用户输出最终答案——本地模型的输出必须经过你（主模型）的审查
- ❌ 不要同一轮任务内不要并发请求本地 coder 模型
