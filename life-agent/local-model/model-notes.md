# Qwen3.5-9B 本地多模态推理：模型、参数与实测记录

本文件只记录**路径、参数与实测数据**，不记录也不提交任何模型权重文件。

## 1. 选型：为什么是 Q4_K_M + mmproj-F16

- **主模型 `Qwen3.5-9B-Q4_K_M.gguf`**：Q4_K_M 是 9B 级模型在 12 GB 显存笔记本显卡上的实际可用档位。
  更低（Q3_K_M、IQ4_XS）画质与指令跟随下降明显；更高（Q5_K_M、Q6_K、Q8_0）单文件超过 6.5 GB，
  叠加视觉投影器与 KV cache 后必然显存溢出，只能大量落到 CPU，解码速度塌到个位数 tok/s。
  Q4_K_M 的 k-quant 混合量化在 4 bit 档里误差最小，是质量与体积的平衡点。
- **投影器 `mmproj-F16.gguf`**：视觉塔只做一次前向，计算量远小于主模型，压缩到 Q8/BF16 收益很小，
  而错误的投影量化会直接损伤图像理解质量。F16 是官方提供的全精度选项，约 0.92 GB，代价可接受。
  仓库里另有 F32（约 1.8 GB，纯浪费显存）与 BF16（与 F16 精度等价但兼容性更差），因此选 F16。
- **不下载更大模型**：本机 12 GB 显存的可用余量（桌面程序常驻占用 4.4–5.3 GB）决定了 9B Q4 是上限。

## 2. 参数表：基线值与实测最优值

| 参数 | 基线值 | 实测最优值 | 含义与调优方向 |
| --- | --- | --- | --- |
| `-c`（`--ctx-size`） | 32768 | **16384** | 上下文长度。本机实测：16384 时解码约 7–21 tok/s，显存总量约 11.4–11.5 GB。往上调到 32768 仍能加载（不 OOM），但总显存逼近 12.2 GB 上限、解码掉到约 4.6 tok/s，属于「显存换上下文」的亏本交易。余量更大时可向上试 20480/32768；换到 16 GB 以上显卡可直接取 32768。 |
| `-ngl`（`--n-gpu-layers`） | 28 | **99** | 卸载到 GPU 的层数，99 表示全部层。基线 28 层时约 1/6 的层留在 CPU，解码仅 3.4 tok/s；全量卸载后同尺寸上下文提升 2–6 倍。调优方向：始终先试满（99），再靠降低 `-c` 或关闭其它 GPU 程序腾显存，而不是降层数。 |
| `--reasoning-budget` | 0 | **0** | 思考链预算。0 = 立刻结束思考、直接给答案，本地小模型上这一步能省掉大量无意义 token。需要看推理过程时改成 -1（不限）或一个正整数。 |
| `--mmproj` | `mmproj-F16.gguf` | **`mmproj-F16.gguf`** | 视觉投影器路径。必须与主模型配套（同仓库同一版本），否则图像特征维度不匹配。 |
| `--host` | 0.0.0.0 | **127.0.0.1** | 监听地址。默认只绑回环地址，仅本机可访问；需要局域网访问时显式传 0.0.0.0（0.0.0.0 表示监听所有网卡，同网段任何机器都能调用，且服务无鉴权）。 |
| `--port` | 8080 | **8090** | 监听端口。本机 127.0.0.1:8080 被 Steam 的 steamwebhelper 占用，8080 上的请求到不了模型，故默认用 8090；端口再被占用时只改这里，不影响模型参数与第 3 节实测值。 |

## 3. 实测记录

### 3.1 测试环境

- GPU：NVIDIA GeForce RTX 5070 Ti Laptop GPU，12227 MiB，驱动 621.01（Blackwell sm_120）
- llama.cpp：`version: 0.7.0-dev (build 11853, commit 1ddffe9f7)`，Windows x64 CUDA 构建
  （`llama-b11853-bin-win-cuda-13.4-x64.zip` + `cudart-llama-bin-win-cuda-13.4-x64.zip`）
- 运行目录：`G:\LocalAI\tools\llama.cpp`（含 cudart64_13.dll、cublas64_13.dll、cublasLt64_13.dll）
- 模型文件实际字节数：`Qwen3.5-9B-Q4_K_M.gguf` = 5868826976，`mmproj-F16.gguf` = 918165984
- 请求：640×480 PNG（红色圆形、蓝色三角形、黄色矩形，文字 QWEN 42 / HELLO），
  `POST /v1/chat/completions`，prompt 327 tokens（含图像 token），输出约 110 tokens
- 干扰因素：测试期间桌面常驻 Wallpaper Engine、Steam、浏览器等程序，GPU 利用率长期 68–88%，
  空闲显存占用 4363–5348 MiB。因此同一组参数的 tok/s 在 5–21 之间波动，属**同机噪声**，不是配置差异。

### 3.2 带图请求结果（HTTP 200）

```
HTTP 200
CONTENT: 这张图片展示了一个带有黑色边框的米色背景，上面分布着三个主要图形和两处文字：
1. 图形与颜色：左侧有一个红色的圆形；右上方有一个蓝色的三角形；右下方有一个黄色的矩形。
2. 文字：红色圆形的左下方写着黑色的"OWEN 42"；黄色矩形的内部写着黑色的"HELLO"。
TIMINGS: {"prompt_n": 4, "prompt_ms": 173.55, "prompt_per_second": 23.05,
          "predicted_n": 109, "predicted_ms": 5141.13, "predicted_per_second": 21.01}
```

图形、颜色、位置与两处文字全部识别正确；"QWEN 42" 被读成 "OWEN 42"（Q 与 O 混淆），
属于 4 bit 量化下的小字号 OCR 误差，不影响图像理解能力判定。

### 3.3 显存与吞吐采样（nvidia-smi memory.used，单位 MiB）

| 配置 | 解码速度 tok/s（同实例多次） | 显存总量峰值 | 扣掉桌面占用后模型占用 |
| --- | --- | --- | --- |
| `-c 32768 -ngl 28`（基线） | 3.36 | 11504 | 约 6900 |
| `-c 32768 -ngl 99` | 4.64 / 3.82 / 8.35（中位 4.64） | 11602 | 7047 |
| `-c 20480 -ngl 99` | 13.46 / 18.05 / 16.13；另一轮 6.89 / 7.00 / 11.67 | 11563 | 7200 |
| `-c 16384 -ngl 99`（最终值） | 8.34 / 6.39 / 7.17；另两轮 5.98 / 10.31 与 21.01 | 11540 | 6187–7028 |
| `-c 8192 -ngl 99` | 9.47 / 12.15 / 13.40（中位 12.15） | 11503 | 6706 |

首 token 延迟（327 tokens 的带图 prompt）：约 0.48–1.2 s；图像 token 被缓存后约 0.17 s。

### 3.4 OOM 边界

- **没有出现真正的 OOM**：`-c 32768 -ngl 99` 也能完整加载并正常返回。
- 真实边界是**显存余量耗尽后的速度塌陷**：模型占用 7.0 GB + 桌面程序 4.4–5.3 GB 后，
  总占用达到 11.5–11.6 GB / 12.2 GB，只剩约 0.6 GB 余量，解码速度从 12 tok/s 级别掉到 4.6 tok/s 级别。
- 因此 `-c` 的上限不是由「能不能装下」决定，而是由「装下之后还剩多少余量」决定。
- 同时观察到 `-c 22528` 一轮出现 2.93 tok/s 的异常低值，与上述速度塌陷一致。

### 3.5 结论

- `-ngl 99` + `-c 16384` 是这台机器上「不 OOM、留有余量、速度可接受」的最优点：
  模型占用约 6.2–7.0 GB，总占用约 11.4–11.5 GB，解码 7–21 tok/s，首 token 约 1 s。
- 若关闭 Wallpaper Engine / Steam 等占用 GPU 的桌面程序，显存与算力余量会明显变大，
  可以再向上试 `-c 20480` 甚至 `-c 32768`。

## 4. 仓库只记录路径与参数，不提交模型文件

本目录只保存启动脚本与本文档。`.gguf` 权重文件一律不进入仓库：
主模型与投影器放在 `G:\LocalAI\models\Qwen3.5-9B\`，llama.cpp 二进制与 CUDA 运行库放在
`G:\LocalAI\tools\llama.cpp\`，两者都在仓库之外，仓库里只出现它们的路径字符串。

## 5. 端口冲突（本机特有）

本机 `127.0.0.1:8080` 已被 Steam 的 `steamwebhelper.exe`（PID 24708，netstat 显示 LISTENING）占用：
把服务绑到 8080 后，发往 `127.0.0.1:8080` 的请求会打到 Steam 而不是模型，DSH 端点也就接不上推理服务。
因此**最终默认监听改为 `127.0.0.1:8090`**。

- 选 8090：实测空闲；同时默认只绑回环地址，不把没有鉴权的推理服务暴露到局域网。
- 需要局域网访问：显式传 `-HostAddr 0.0.0.0`（实测可正常绑定），注意此时同网段任何机器都能调用本服务。
- 若 8090 也被占用：只改 `-Port` 即可，端口不影响模型参数与第 3 节的实测值。
- 关闭 Steam 后 8080 空出来，也可以直接 `-Port 8080`。

## 6. 复现步骤

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

# 6. 启动（默认 127.0.0.1:8090；需要局域网访问时加 -HostAddr 0.0.0.0）
powershell -ExecutionPolicy Bypass -File .\start-llama-server.ps1

# 7. 带图请求自检（PowerShell）
$img = [Convert]::ToBase64String([IO.File]::ReadAllBytes("G:\LocalAI\logs\test-image.png"))
$body = @{ model="qwen"; max_tokens=200; messages=@(@{ role="user"; content=@(
  @{ type="text"; text="用简洁的中文描述这张图片的主要内容，包括图形、颜色和文字。" },
  @{ type="image_url"; image_url=@{ url="data:image/png;base64,$img" } }) }) } | ConvertTo-Json -Depth 10
Invoke-RestMethod -Uri "http://127.0.0.1:8090/v1/chat/completions" -Method Post -ContentType "application/json; charset=utf-8" -Body $body

# 8. 边请求边看显存
nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv -l 1
```
