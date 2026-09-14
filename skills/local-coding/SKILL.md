---
name: local-coding
description: 编程任务优先走本地 LM Studio 代码模型（默认 qwen3-coder-30b-a3b-instruct）Q6 量化版（`coder-deep`）是质量优先档，仅当用户声明"不限时长 / 尽量好"时用。；代码审查走 local_review 工具（源文件不进主模型上下文）；复杂决策、跨文件重构、架构设计仍交主模型
whenToUse: 写代码、解释代码、审查代码、生成测试/样板、格式化转换、正则/SQL 生成
---

# 本地编程（Local Coding）

编码任务按"有界 / 复杂"分流：**有界任务走本地代码模型**（省 token、离线可用），
**复杂决策留主模型**（跨文件重构、架构设计、疑难 bug）。

本地代码模型**不消耗主模型 token、不计费**。

## ⚠️ 省 token 的关键：文件读取必须发生在主模型上下文之外

**不要自己读文件再发给本地 coder。** 只要你调用了 `read_file`，
文件内容就已经进入你的上下文、已经扣了 token，无论后面发给谁。

节省发生在工具层：**你只传路径，工具读文件、调本地模型、只把结果返回给你。**

所以：

- 代码**审查** → 调用 `local_review` 工具（见下），不要自己读文件
- 代码**编写** → 目前没有工具层支持，自己读上下文文件后调 router（这部分省不了）

## 分工原则

| 任务类型                                                          | 走哪里              | 说明                                 |
| ----------------------------------------------------------------- | ------------------- | ------------------------------------ |
| 少量文件审查 / 代码解释 / 正则 / SQL / 格式转换                   | `local_review` 工具 | 源文件不进你的上下文，**最省 token** |
| 生成测试 / 样板代码（单文件、可一眼验证）                         | router 直调         | 上下文小，自己读几个文件也能接受     |
| 模糊请求 / 复杂 bug / 跨文件重构 / 架构设计 / 性能优化 / 安全审计 | 主模型（你）        | 本地模型看不到全貌，别用             |

**判断依据**：

- 只看少量文件、或答案可以一眼验证 → 本地
- 须完整查看大量文件内容、或需要设计决策 → 主模型

## 模型

| 别名                          | 实际模型                     | 大小 / 量化     | 场景                             |
| ----------------------------- | ---------------------------- | --------------- | -------------------------------- |
| `coder`（默认）               | `qwen3-coder-30b`            | 17.35G / Q4_K_M | **常态主力**                     |
| `coder-fast`                  | `qwen2.5-coder-14b-instruct` | 8.37G / Q4_K_M  | 显存紧张 / 给视觉腾地方          |
| `coder-deep`                  | `qwen/qwen3-coder-30b`       | 23.38G / Q6_K   | 质量优先，用户声明"不限时长"时用 |
| `auto` / `vision` / `default` | `qwen2.5-vl-7b-instruct`     | 5.62G / Q4_K_M  | 视觉（见 `local-vision` skill）  |

**一次只加载一个模型**（显存限制）。同一轮任务固定用一个模型——切换一次 7-10 秒。

**重要**：切换到本地代码模型会卸载当前视觉模型，反之亦然。不要在同一轮任务里交叉使用编码和识图。

**降级链**：请求 `coder-deep` 时，若 Q6 未下载或加载失败，router 会自动降级：
`coder-deep (Q6)` → `coder (Q4)` → `coder-fast (14B)` → 503 报错。
响应会带 `fallback_used: true`，日志打 `FALLBACK` 前缀。
DSH 拿到 503 时**不要重试、不要静默**，直接告诉用户缺少哪个模型、
当前有哪些可用，让用户决定下一步。

## 如何使用

### 方式一：`local_review` 工具（代码审查首选）

**这是省 token 的核心路径。** 你只传路径，工具读文件。

```bash
TOOLS=${LMSTUDIO_TOOLS:-<DSH仓库根>/custom/tools/LMStudio}

# 基本用法
python "$TOOLS/local_review.py" src/auth.ts --focus "边界条件和错误处理"

# 多文件
python "$TOOLS/local_review.py" src/auth.ts src/user.ts

# 深度模式（用户声明不限时长时）
python "$TOOLS/local_review.py" src/auth.ts --mode coder-deep
```

工具输出即审查意见。**不要把源文件读进你的上下文再传给它**——那就白做了。

### 方式二：router 直调（编写、解释、生成草稿）

两个端点都是 OpenAI 兼容。**这条路需要你自己读上下文文件**，所以只适合小上下文任务。

```bash
ROUTER=${LMSTUDIO_ROUTER_BASE:-http://127.0.0.1:1235}

# 默认（Qwen2.5-Coder-14B）
curl -s -m 300 "$ROUTER/v1/chat/completions" -H 'Content-Type: application/json' -d '{
  "model": "coder",
  "messages": [{"role":"user","content":"解释下面这段代码的边界条件\n<代码片段>"}],
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

## 何时调 local_review，何时自己读文件

| 情况                                        | 做法                                             |
| ------------------------------------------- | ------------------------------------------------ |
| 审查 1-3 个文件，问题是"这段代码有没有问题" | **调 `local_review`**，不要自己读                |
| 需要跨文件追踪调用链、理解数据流            | 自己读（本地模型看不到全貌，会给出错误结论）     |
| 需要跑测试/编译才能验证                     | 自己做（本地模型不能执行代码）                   |
| 用户问的是"为什么这样设计"（需要项目历史）  | 自己答（本地模型没有项目记忆）                   |
| 只是格式化、改命名、加注释                  | **调 `local_review`** 或 router 直调，不必自己读 |

**核心判断**：如果你读完文件后，还要自己做跨文件推理或设计决策，那不如自己读——
`local_review` 只适合"意见可以直接用"的场景。

## 上下文控制（走 router 直调时）

本地模型显存有限（12GB），**不要整项目塞进去**。喂之前先裁剪：

1. **只给相关文件**：只给当前任务相关的那几个文件 + 相关类型定义
2. **截断文件内容**：只给相关函数或类，不要整文件
3. **不要带完整日志**：日志/编译输出先 `head -c 4000` 或提炼成要点
4. **不要带历史对话**：一轮独立任务用一个新会话
5. **理想上下文**：16K 以下。12GB 显存下 16K 是舒适上限

走 `local_review` 时这一层由工具处理（单文件上限 30000 字符、总量 80000 字符，
可用 `LOCAL_REVIEW_PER_FILE_LIMIT` / `LOCAL_REVIEW_TOTAL_LIMIT` 覆盖）。

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
4. **模型加载失败（显存不够 / 未下载）→ router 已自动降级**。
   查看响应体或日志里的 `fallback_used` / `FALLBACK` 标记，确认实际用的是哪个模型。
   若最终返回 503，说明整个降级链都不可用——按第 5 步处理。
5. **本地全部失败 → 主模型兜底**：直接自己处理，并告知用户"本地代码模型不可用"
6. **不要在没有用户同意时**把任务转给外部 API

## 故障排查

| 现象                         | 处理                                                     |
| ---------------------------- | -------------------------------------------------------- |
| `curl` 连不上 1235           | router 没起来，按降级第 2 步启动                         |
| `local_review.py` 报读取失败 | 路径写错或文件是二进制；检查后重试                       |
| 请求成功但 `content` 空串    | 换 `coder-deep` 重试，或换视觉模型确认不是 router 问题   |
| 首个请求特别慢（7-10s+）     | 正常：正在切换模型                                       |
| 速度很慢（< 10 tok/s）       | 可能在用 `coder-deep`（CPU offload）。切回 `coder` 即可  |
| 显存吃紧                     | `python "$TOOLS/lmstudio_router.py" unload --all`        |
| 同时需要视觉任务             | 不要同轮混用。先做完编码任务再切视觉；或先做视觉再切编码 |

## 成本说明

本地推理**不计费、不消耗主模型上下文**。但两条路径的节省差别很大：

| 路径                         | 源文件进主模型上下文？ | 主模型 token 消耗（300 行文件审查） |
| ---------------------------- | ---------------------- | ----------------------------------- |
| 自己 `read_file` 再调 router | 是（~3000 token）      | ~3500 token                         |
| **调 `local_review` 工具**   | **否**                 | **~530 token（省 ~85%）**           |

**结论**：审查任务必须走 `local_review`，自己读文件再转发等于没省。

## 不要做的事

- ❌ 自己 `read_file` 后再调本地 coder 做审查（文件已进上下文，token 已花）
- ❌ 把整个项目塞给本地模型（显存扛不住，上下文会溢出）
- ❌ 让本地模型做架构设计、跨文件重构（做不好，反而浪费你的审查时间）
- ❌ 在同一轮任务里混用 coder 和 vision（每次切换 7-10 秒）
- ❌ 用户没说"不限时长"就用 `coder-deep`（速度慢，影响体验）
- ❌ 让本地模型的输出直接对用户呈现——必须经过你的审查
- ❌ 同一轮任务内并发请求本地 coder 模型（router 的切换锁只在加载阶段持锁，转发阶段并发会误卸载在用模型）
