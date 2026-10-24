# Qwen3.5-9B 本地多模态推理：模型、参数与实测记录

本文件只记录**路径、参数与实测数据**，不记录也不提交任何模型权重文件。

## 1. 选型：为什么是 Q4_K_M + mmproj-F16

- **主模型 `Qwen3.5-9B-Q4_K_M.gguf`**：Q4_K_M 是 9B 级模型在 12 GB 显存笔记本显卡上的实际可用档位。
  更低（Q3_K_M、IQ4_XS）画质与指令跟随下降明显；更高（Q5_K_M、Q6_K、Q8_0）单文件超过 6.5 GB，
  叠加视觉投影器与 KV cache 后必然显存溢出，只能大量落到 CPU，解码速度塌到个位数 tok/s。
  Q4_K_M 的 k-quant 混合量化在 4 bit 档里误差最小，是质量与体积的平衡点。
- **投影器 `mmproj-F16.gguf`**：视觉塔只做一次前向，计算量远小于主模型，压缩到 Q8/BF16 收益很小，
  而错误的投影量化会直接损伤图像理解质量。F16 是官方提供的全精度选项，约 0.92 GB，代价可接受。
  实测它常驻显存约 1126 MiB：不需要图像输入时，去掉 `--mmproj` 能省下这部分（见 3.2 表末行）。
- **不下载更大模型**：本机 12 GB 显存的可用余量决定了 9B Q4 是上限。提高可用上下文靠 `-c` 与
  KV cache 量化，不靠换模型（换量化档或换小模型是另一件事，见第 4 节）。

## 2. 参数表：基线值与实测最优值

| 参数 | 基线值 | 实测最优值 | 含义与调优方向 |
| --- | --- | --- | --- |
| `-c`（`--ctx-size`） | 16384 | **49152** | 上下文长度。DSH 一次会话请求实测到 **38565 tokens**，16384 与 32768 都会被服务端拒绝，所以必须 ≥ 38565；49152 还额外留出约 10k 输出空间。显存吃紧时按 49152 → 40960 → 32768 降，但低于 38565 那类请求会直接失败（不是变慢）。 |
| `-ctk`（`--cache-type-k`） | f16 | **q8_0** | K cache 量化类型。在 `-c 49152` 下把模型显存占用从 f16 的 7888 MiB 压到 7341 MiB（省 547 MiB），解码速度实测无差异。 |
| `-ctv`（`--cache-type-v`） | f16 | **q8_0** | V cache 量化类型。再紧一档可换 `q4_0`（49152 下再省约 190–380 MiB）；39.8k 长上下文召回实测 q8_0 与 q4_0 一致（见 3.4），但 q4_0 是可选加速退路，默认不用。 |
| `-fa`（`--flash-attn`） | auto | **on** | Flash attention。V cache 量化在部分构建里要求开启 FA，且长上下文 prefill 明显更快。固定 `on` 避免 auto 落到 off 时行为与实测不符。 |
| `-np`（`--parallel`） | auto | **1** | 并行槽位。1 = 整个 `-c` 归单个请求；多槽位会把上下文切分到各槽位，长请求更容易被拒。DSH 是单请求串行，取 1。 |
| `-ngl`（`--n-gpu-layers`） | 28 | **99** | 卸载到 GPU 的层数，99 表示全部层。基线 28 层时约 1/6 的层留在 CPU，解码仅 3.4 tok/s；全量卸载后提升 2–6 倍。调优方向：始终先试满（99），再靠降 `-c` 或关闭其它 GPU 程序腾显存，而不是降层数。 |
| `--reasoning-budget` | 0 | **0** | 思考链预算。0 = 立刻结束思考、直接给答案，本地小模型上这一步能省掉大量无意义 token。需要看推理过程时改成 -1（不限）或一个正整数。 |
| `--mmproj` | `mmproj-F16.gguf` | **`mmproj-F16.gguf`** | 视觉投影器路径。必须与主模型配套（同仓库同一版本），否则图像特征维度不匹配。 |
| `--host` | 0.0.0.0 | **127.0.0.1** | 监听地址。默认只绑回环地址，仅本机可访问；需要局域网访问时显式传 0.0.0.0（同网段任何机器都能调用，且服务无鉴权）。 |
| `--port` | 8080 | **8090** | 监听端口。本机 127.0.0.1:8080 被 Steam 的 steamwebhelper 占用，8080 上的请求到不了模型，故默认用 8090；端口再被占用时只改这里，不影响模型参数与实测值。 |

## 3. 实测记录

### 3.1 测试环境与测量方法

- GPU：NVIDIA GeForce RTX 5070 Ti Laptop GPU，12227 MiB，驱动 621.01（Blackwell sm_120）
- llama.cpp：`version: 0.7.0-dev (build 11853, commit 1ddffe9f7)`，Windows x64 CUDA 构建
- 模型文件实际字节数：`Qwen3.5-9B-Q4_K_M.gguf` = 5868826976，`mmproj-F16.gguf` = 918165984
- **显存占用一律指「模型占用」**：`nvidia-smi memory.used` 的中位数减去同一时刻的桌面基线。
  桌面基线在每组测试前后各采样一次取中位数，两组都记了才相减，避免把桌面程序波动算进模型。
  这一列才能和「桌面程序占 4.4–5.3 GB」的现实条件相加。
- **长请求的 token 数是真值不是估计**：用 `/tokenize` 校准长度，最终以服务端日志/响应里的
  `n_prompt_tokens` 与 `usage.prompt_tokens` 为准。
- **长上下文有效性用 needle 验证**，不是只看 HTTP 200：在文档 50% 和 90–95% 深度埋一句
  `RECORD 4741: the vault passphrase for the northern depot is KIWI-7420.`，再问 passphrase，
  检查回答里是否出现 `KIWI-7420`。只回 200 而答不出来，说明长上下文不可用。
- 每组测完都关闭进程，确认 8090 无 LISTENING 后才开下一组（`TIME_WAIT` 残留不算，监听已释放）。

### 3.2 显存-上下文曲线（本机的核心数据，桌面基线 1.5–2.5 GB）

| `-c` | KV 类型 | 模型占用 MiB | 桌面基线 MiB | 合计 MiB |
| --- | --- | --- | --- | --- |
| 2048 | q8_0 | 6361 | 2445 | 8806 |
| 16384 | f16 | 6852 | 2446 | 9298 |
| 16384 | q8_0 | 6637 | 2445 | 9082 |
| 32768 | f16 | 7379 | 2447 | 9826 |
| 32768 | q8_0 | 7095 | 2445 | 9540 |
| 40960 | q4_0 | 6841 | 2449 | 9290 |
| 40960 | q8_0 | 7165 | 2445 | 9610 |
| 49152 | f16 | 7888 | 1536 | 9424 |
| **49152** | **q8_0** | **7341** | 2411 | 9752 |
| 49152 | q8_0 / q4_0（K 高精度） | 7147 | 2411 | 9558 |
| 49152 | q4_0 | 6957 | 2411 | 9368 |
| 49152 | q4_0 + `-ub 256` | 6901 | 2411 | 9312 |
| 65536 | q4_0 | 7181 | 2445 | 9626 |
| 65536 | q8_0 | 7673 | 1517 | 9190 |
| 81920 | q4_0 | 7405 | 2411 | 9816 |
| 40960 | q8_0，**不带 `--mmproj`** | 6039 | 2445 | 8484 |

三个直接结论：

1. **`-c 49152` + q8_0 比旧的 `-c 32768` + f16 还省 38 MiB**（7341 vs 7379）：
   上下文 1.5 倍、显存不涨，KV 量化基本把多出来的上下文额度免费买了下来。
2. 相对当前的 `-c 16384` + f16（6852 MiB），提升到 49152 只多 489 MiB。
3. 权重与计算缓冲约 6.3 GB 是地板（`-c 2048` 也要 6361 MiB），KV 才是随 `-c` 增长的部分，
   所以继续上探时每 8192 tokens 只增加约 70–230 MiB（q8_0）或约 110 MiB（q4_0）；真正卡住上限的是**桌面程序占走的显存**。

### 3.3 速度（同一实例、桌面基线 1.5–2.5 GB 时的实测）

| 配置 | 短 prompt 解码 tok/s | 39.8k prompt 的 prefill tok/s | 39.8k 上下文解码 tok/s |
| --- | --- | --- | --- |
| `-c 32768` + f16 | 80.9 | 2809（32k 长请求） | 50.9 |
| `-c 32768` + q8_0 | 79.7 | 2762 | 48.6 |
| `-c 40960` + q8_0 | 65.9 | 2043 | 47.3 |
| `-c 49152` + q8_0 | 62.0 | 2037–2053 | 46.2 / 47.5 |
| `-c 49152` + q4_0 | 61.2 | 2043 | 45.7 |
| `-c 65536` + q8_0 | — | — | 46.0 |

- prefill 约 2000 tok/s，意味着一次 38.6k tokens 的请求首 token 约 **19–20 s** 才出现；
  这是长上下文的主要代价，比解码速度更值得预期。
- KV 量化对速度**没有**可测影响（q8_0 与 q4_0 都在 45–48 tok/s）。

### 3.4 真实长请求验证（不是只看 200）

用最终参数（`-c 49152 -ctk q8_0 -ctv q8_0 -fa on -np 1`）跑真实请求，日志与响应：

```
n_ctx_slot = 49152, n_slots = 1, kv_unified = 'false'
prompt eval time =   20337.80 ms / 39804 tokens ( 0.51 ms per token, 1957.14 tokens per second)
HTTP 200  usage.prompt_tokens = 39804   predicted = 45.2 tok/s   needle = KIWI-7420（命中）
```

- prompt 39804 tokens **> 38565**（用户实际遇到的长度），请求成功，回答正确召回埋点。
- needle 在文档 50% 与 95% 两个深度都命中（q8_0 与 q4_0 各测一轮，均命中）——
  说明 39.8k 上下文是**可用的**，不只是「装得下」。
- 另测：llama.cpp 只校验 `n_prompt_tokens ≤ n_ctx`，**不**校验 `prompt + max_tokens`。
  实测 `-c 40960` 上 39769 tokens 的 prompt 配 `max_tokens: 4096` 仍返回 200，
  只是在触到 n_ctx 时把生成截断。因此 `-c` 至少要覆盖 prompt 本身；
  想给输出留满 4096 token 的空间则应选 49152 而不是 40960。

### 3.5 桌面压力测试：4.4–5.3 GB 桌面下是否还能跑

用 CUDA 侧占位（torch 常驻 2.9 GB）把桌面占用抬到 4.6–5.3 GB 后，再起服务、再发 39804 tokens 请求：

| 桌面占用 MiB | 配置 | 合计 MiB | 请求结果 | decode tok/s | needle |
| --- | --- | --- | --- | --- | --- |
| 5344 | 40960 + q8_0 | 11533 | 200 | 17.3 | 命中 |
| 4693 | 40960 + q8_0 | 11541 | 200 | 17.0 | 命中 |
| 4666 | 49152 + q8_0 | 11649 | 200 | 18.4 | 命中 |
| 4595 | 49152 + q4_0 | 11444 | 200 | 16.0 | 命中 |
| 4585 | 40960 + q4_0 | 11473 | 200 | 23.4 | 命中 |
| 4586 | 65536 + q8_0 | 11495 | 200 | 43.8 | 命中 |

- **没有一组 OOM**，全部装下并正确回答。总占用稳定停在 11.4–11.6 GB / 12.2 GB；
  也就是说 WDDM 在压力下会把桌面程序的显存页换出去，而不是让服务分配失败。
  代价是速度：桌面吃 4.6–5.3 GB 时解码掉到 **16–24 tok/s**（占位进程不touch显存，
  真实的 Wallpaper Engine / 浏览器会更糟，按一半估算比较稳）。
- 结论：**能不能装下**由显存决定；**跑多快**由桌面程序占多少 GPU 决定的。
  留出显存余量不是为了能启动，而是为了不被换页拖慢。

### 3.6 失败复现：为什么 16384 曾经被拒

`-c 32768` + f16 KV 上发一个 39010 tokens 的 prompt，服务端原样返回：

```json
{"code":400,"message":"request (39010 tokens) exceeds the available context size (32768 tokens), try increasing it",
 "type":"exceed_context_size_error","n_prompt_tokens":39010,"n_ctx":32768}
```

与用户最初遇到的 `n_prompt_tokens=38565, n_ctx=16384` 是同一个错误。**32768 也装不下 38565**，
所以本次把默认值定到 49152 而不是 32768：32768 只是把失败从「必然」推迟到「偶尔」。

### 3.7 对旧记录中「32768 只剩 4.64 tok/s」的修订

旧记录把 32k 上下文判成「显存换上下文的亏本交易」，依据是 4.64 tok/s。本次用**同样参数**
（`-c 32768 -ngl 99` + f16 KV）重测，短 prompt 解码 80.9 tok/s、32k 长请求 50.9 tok/s，
相差近 10–17 倍。差别不在参数，而在**测速时的 GPU 负载**：旧记录里桌面程序让 GPU 利用率
长期停在 68–88%，那份 4.64 tok/s 是算力争用，不是上下文长度的代价。

因此本文件不再用速度来否决大上下文；选 `-c` 的依据是显存余量（3.2 / 3.5），速度只作为验收线：
桌面压力下仍 ≥ 16 tok/s，远高于「< 2 tok/s 不可用」的回退门槛。

## 4. 结论：为什么是 `-c 49152` + `q8_0` KV + `-fa on`

- **能装**：模型占用 7341 MiB。桌面 1.5–2.5 GB 时合计 9752 MiB（余量约 2.4 GB）；
  桌面 4.6 GB 时合计 11649 MiB，仍能装下 39804 tokens 的请求（3.5 实测）。
- **装的是真需要的东西**：38565 tokens 的实际请求 + 约 10k tokens 输出空间；
  40960 虽然也能过 39769 的长 prompt，但 prompt + 4096 输出就会顶到 n_ctx 被截断。
- **不比现状贵**：7341 MiB 比旧默认（16384 + f16，6852 MiB）只多 489 MiB，
  比旧「上探值」（32768 + f16，7379 MiB）还少 38 MiB。
- **速度不塌**：安静桌面 46–47 tok/s，4.6 GB 桌面压力下 16–24 tok/s。
- **质量有验证**：39.8k 上下文在 50% / 95% 两个深度都能召回埋点，q8_0 与 q4_0 都对。
- **为什么不再往上**：65536 + q8_0 要多 332 MiB（7673 MiB），换来的上下文用户用不到，
  却把「桌面吃 5 GB 时还宽裕」变成「靠 WDDM 换页撑着」。81920 同理（q4_0 也要 7405 MiB）。
- **显存更紧时的退路**（按顺序）：`-CTX 40960` → `-ctv q4_0`（省约 190 MiB）→
  `-CTX 32768`（此时 38565 tokens 的那类请求会失败）→ 不带 `--mmproj`（省 1126 MiB，放弃图像输入）。

## 5. 仓库只记录路径与参数，不提交模型文件

本目录只保存启动脚本与本文档。`.gguf` 权重文件一律不进入仓库：
主模型与投影器放在 `G:\LocalAI\models\Qwen3.5-9B\`，llama.cpp 二进制与 CUDA 运行库放在
`G:\LocalAI\tools\llama.cpp\`，两者都在仓库之外，仓库里只出现它们的路径字符串。

## 6. 端口冲突（本机特有）

本机 `127.0.0.1:8080` 已被 Steam 的 `steamwebhelper.exe` 占用（netstat 显示 LISTENING）：
把服务绑到 8080 后，发往 `127.0.0.1:8080` 的请求会打到 Steam 而不是模型，DSH 端点也就接不上推理服务。
因此**最终默认监听改为 `127.0.0.1:8090`**。

- 选 8090：实测空闲；同时默认只绑回环地址，不把没有鉴权的推理服务暴露到局域网。
- 需要局域网访问：显式传 `-HostAddr 0.0.0.0`（实测可正常绑定），注意此时同网段任何机器都能调用本服务。
- 若 8090 也被占用：只改 `-Port` 即可，端口不影响模型参数与第 3 节的实测值。
- 关闭 Steam 后 8080 空出来，也可以直接 `-Port 8080`。

## 7. 复现步骤

```powershell
# 1. 建目录
New-Item -ItemType Directory -Force G:\LocalAI\tools, G:\LocalAI\models\Qwen3.5-9B, G:\LocalAI\logs

# 2. 取 llama.cpp 的 Windows CUDA 构建版本号（github.com 主页不通，改走 api.github.com）
curl.exe -sS --ssl-no-revoke "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=1"

# 3. 下载两个 zip 并解压到 G:\LocalAI\tools\llama.cpp（含 CUDA 运行库，缺库时 llama-server 只认 CPU）
curl.exe -L --ssl-no-revoke -o G:\LocalAI\tools\llama.zip     "https://github.com/ggml-org/llama.cpp/releases/download/b11853/llama-b11853-bin-win-cuda-13.4-x64.zip"
curl.exe -L --ssl-no-revoke -o G:\LocalAI\tools\cudart.zip    "https://github.com/ggml-org/llama.cpp/releases/download/b11853/cudart-llama-bin-win-cuda-13.4-x64.zip"
Expand-Archive G:\LocalAI\tools\llama.zip  G:\LocalAI\tools\_l -Force
Expand-Archive G:\LocalAI\tools\cudart.zip G:\LocalAI\tools\_c -Force
Copy-Item G:\LocalAI\tools\_l\* G:\LocalAI\tools\llama.cpp\ -Recurse -Force
Copy-Item G:\LocalAI\tools\_c\* G:\LocalAI\tools\llama.cpp\ -Recurse -Force

# 4. 下载模型（hf CLI 在本机会因上游代理缺少 X-Repo-Commit 响应头而失败，改用 resolve 直链 + 镜像）
#    文件大小核对：5868826976 / 918165984
curl.exe -L --ssl-no-revoke -C - -o "G:\LocalAI\models\Qwen3.5-9B\Qwen3.5-9B-Q4_K_M.gguf" "https://hf-mirror.com/unsloth/Qwen3.5-9B-MTP-GGUF/resolve/main/Qwen3.5-9B-Q4_K_M.gguf"
curl.exe -L --ssl-no-revoke -C - -o "G:\LocalAI\models\Qwen3.5-9B\mmproj-F16.gguf"          "https://hf-mirror.com/unsloth/Qwen3.5-9B-MTP-GGUF/resolve/main/mmproj-F16.gguf"

# 5. 确认 GPU 可见
G:\LocalAI\tools\llama.cpp\llama-server.exe --list-devices

# 6. 启动（默认 127.0.0.1:8090、-c 49152；显存吃紧时加 -CTX 40960）
F:\Projects\deepseek-harness\custom\life-agent\local-model\start-llama-server.ps1

# 7. 确认 n_ctx 真的是 49152（脚本输出里就有这一行）
#    0.05.737.367 I srv load_model: initializing, n_slots = 1, n_ctx_slot = 49152, kv_unified = 'false'

# 8. 带图请求自检（PowerShell）
$img = [Convert]::ToBase64String([IO.File]::ReadAllBytes("G:\LocalAI\logs\test-image.png"))
$body = @{ model="qwen"; max_tokens=200; messages=@(@{ role="user"; content=@(
  @{ type="text"; text="用简洁的中文描述这张图片的主要内容，包括图形、颜色和文字。" },
  @{ type="image_url"; image_url=@{ url="data:image/png;base64,$img" } }) }) } | ConvertTo-Json -Depth 10
Invoke-RestMethod -Uri "http://127.0.0.1:8090/v1/chat/completions" -Method Post -ContentType "application/json; charset=utf-8" -Body $body

# 9. 边请求边看显存
nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv -l 1
```

### 7.1 重做一次长上下文测量（改参数后必跑）

1. 起服务，等 `/health` 返回 `{"status":"ok"}`，记下日志里的 `n_ctx_slot`。
2. 用 `/tokenize` 校准一个长文本的长度（`POST /tokenize` 带 `{"content": "..."}`，数 `tokens` 长度），
   构造略小于 `-c` 的 prompt，末尾加一句提问。
3. `POST /v1/chat/completions`，`max_tokens` 给 4096，检查 **HTTP 200** 和响应里的
   `timings.prompt_n`（应等于你构造的长度）与 `timings.predicted_per_second`。
4. 在长文本 90% 深度埋一句带唯一串的话，问它那句话里的值，确认回答里真有那个串——
   这是「长上下文可用」与「只是没报错」的分界。
5. 记 `nvidia-smi memory.used` 时先记桌面基线（关掉服务时）/ 再记带模型的，两者相减才是模型占用。

## 8. 在 DSH 中接入这个端点（实测可用）

本节记录「怎么让 DSH 把请求打到上面的 llama-server」，配置本身在 DSH 的 profile 里（不入库），
这里只留可复现的写法与理由，换机器时照抄即可。

### 8.1 前置

llama-server 不是常驻服务，会话前需要先启动：

```powershell
F:\Projects\deepseek-harness\custom\life-agent\local-model\start-llama-server.ps1
```

确认端点活着，再启动 DSH 会话：

```powershell
curl http://127.0.0.1:8090/health          # 期望 {"status":"ok"}
curl http://127.0.0.1:8090/v1/models      # 记下返回的真实模型 id
```

### 8.2 接入位置与写法

接入点是 `@deepseek-ai/dsh-llm-pi-ai` 的 `providers` 字典。写进目标 profile 的
`cordis.patch.yml`（本机为 `~/.dsh/profiles/life/cordis.patch.yml`）：

```yaml
- id: llm-pi-ai
  config:
    providers:
      local-qwen:
        displayName: 本地 Qwen3.5-9B (llama.cpp)
        api: openai-completions
        baseURL: 'http://127.0.0.1:8090/v1'
        models:
          - id: 'G:\LocalAI\models\Qwen3.5-9B\Qwen3.5-9B-Q4_K_M.gguf'
            name: Qwen3.5-9B (Q4_K_M)
            contextWindow: 45000
            maxTokens: 4096
            input: [text, image]
```

### 8.3 `contextWindow` 为什么写 45000 而不是 49152

服务端 `-c 49152` 是硬上限，超了就是本文档第 3.6 节那种 `exceed_context_size_error` 400。
DSH 那边 `contextWindow` 决定它什么时候压缩历史，用的是**它自己的 token 估算**，
和 llama-server 的 tokenizer 计数不会逐 token 相等（chat template、图像 token、估算误差都会造成偏差）。
若把两者设成同一个数，估算少算一点就会把请求推到 `n_ctx` 之上，正好复现用户最初那次 400。
45000 留了约 4150 tokens（9%）的余量：真到顶时是 DSH 先压缩，而不是服务端先报错。

- 若服务端改用 `-CTX 40960`：`contextWindow` 相应降到 **36864**（同样留 10%）。
- 若服务端改用 `-CTX 32768`：`contextWindow` 写 **30000**。注意此时 38565 tokens 的会话仍会被拒——
  降 `-c` 是腾显存的退路，不是解决超长会话的办法。

### 8.4 四个容易踩的点

- **模型 id 是 llama.cpp 返回的完整文件路径**，不是 `qwen` 之类的短名。必须与 `/v1/models` 的
  `data[0].id` 逐字一致，否则请求匹配不上。
- **不要设 `apiKeyEnv`**。llama-server 无鉴权；设一个不存在的环境变量会让解析以
  `MISSING_CREDENTIAL` 失败。省略即不带凭据。
- **`api` 取 `openai-completions`**（该插件支持的协议之一，另有 `openai-responses`、
  `anthropic-messages`，由运行时枚举确认）。
- **profile patch 层是整体替换 `config` 对象**，不是逐键合并。覆盖 `llm-pi-ai` 时要把
  `providers` 整个写全；同一文件里别的条目（例如 `vdesktop`）也必须各自重述全部键，否则会被删空。

### 8.5 验证

```powershell
dsh --profile life --dump-config   # 期望 exit 0 且 stderr 为空
```

再在 dump 里确认 `local-qwen` 的 `baseURL` 与 `vdesktop` 的 `sidecarCwd` 同时存在。

### 8.6 与 DeepSeek API 的切换

本配置只是**新增一条可选路由**，不改变默认模型：`agent-default-model` 未改动，
默认仍走原来的 DeepSeek。要让生活型 Agent 用本地模型，在会话里切到 `local-qwen` 路由即可；
切换时记得先启动 llama-server，否则连接被拒。

### 8.7 长上下文请求的预期节奏

- 首 token 约 **19–20 s**（39804 tokens prefill ≈ 1957 tok/s），之后解码 45 tok/s 量级；
  桌面程序吃 4.6 GB 显卡时解码降到 16–24 tok/s。
- 想把首 token 等时压下来，只能减少请求里的历史长度（靠 `contextWindow` 触发的压缩），
  单纯把 `-c` 调大不会加快 prefill。
