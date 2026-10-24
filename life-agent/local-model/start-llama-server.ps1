<#
  Qwen3.5-9B 多模态本地推理服务启动脚本（llama.cpp / llama-server）。

  下面的 -c / -ctk / -ctv / -fa 是**基线参数，部署后需实测调优**的结果：当前值来自本机实测
  （RTX 5070 Ti Laptop，12227 MiB，llama.cpp build 11853，CUDA 13.4 构建），
  换机器、换驱动或换量化后需要重新实测，方法见同目录 model-notes.md 的「复现步骤」。

  为什么默认 -c 从 16384 提到 49152：DSH 一次会话请求实测达到 38565 tokens，
  -c 16384 会被拒绝（400 exceed_context_size_error，n_prompt_tokens=38565，n_ctx=16384），
  -c 32768 同样装不下。提到 49152 后用 KV cache 量化（-ctk/-ctv q8_0）+ -fa on 压显存：
  实测 -c 49152 + q8_0 KV 的模型显存占用为 7341 MiB，比旧的 -c 32768 + f16 KV（7379 MiB）
  还少 38 MiB，即「上下文 1.5 倍、显存不涨」。详见 model-notes.md 第 3 节。

  显存吃紧时按 49152 → 40960 → 32768 降 -c（-CTX 参数），或把 -ctv 换成 q4_0；
  注意 -c 低于 38565 时，那类超长请求会直接失败，不是变慢。

  监听默认 127.0.0.1:8090：本机 127.0.0.1:8080 已被 Steam 的 steamwebhelper 占用（实测该端口上的
  请求会打到 Steam 而不是模型），所以默认端口避开 8080、改用 8090；同时默认只绑回环地址，
  不把没有鉴权的推理服务暴露到局域网。需要局域网访问时显式传 -HostAddr 0.0.0.0，
  注意此时同网段任何机器都能调用本服务且没有鉴权。详见 model-notes.md「端口冲突」一节。
#>
param(
    [string]$HostAddr = '127.0.0.1', # --host：默认只绑回环地址，仅本机可用；需要局域网访问时显式传 -HostAddr 0.0.0.0（服务无鉴权）
    [int]$Port = 8090,               # --port：默认 8090，避开被 Steam 占用的 127.0.0.1:8080；端口被占用时改这里即可
    [int]$CTX  = 49152               # -c：默认 49152（实测最优）；显存吃紧时按 40960 → 32768 降，低于 38565 会拒绝超长请求
)

$ErrorActionPreference = 'Stop'

# ---- 路径：集中定义，只改这里 ----
$LLAMA  = 'G:\LocalAI\tools\llama.cpp'                              # llama-server.exe 与 CUDA 运行库所在目录
$MODEL  = 'G:\LocalAI\models\Qwen3.5-9B\Qwen3.5-9B-Q4_K_M.gguf'    # 主模型（Q4_K_M）
$MMPROJ = 'G:\LocalAI\models\Qwen3.5-9B\mmproj-F16.gguf'           # 视觉投影器（F16）

# ---- 运行时参数：必须与 model-notes.md 的「实测最优值」一致 ----
$NGL      = 99             # -ngl：卸载到 GPU 的层数（99 = 全部层；实测最优）
$BUDGET   = 0              # --reasoning-budget：0 表示不输出思考链
$KVK      = 'q8_0'         # -ctk：K cache 量化类型；f16 → q8_0 在 -c 49152 下省约 550 MiB，速度无差异
$KVV      = 'q8_0'         # -ctv：V cache 量化类型；显存更紧时可换 q4_0（再省约 190 MiB，长上下文召回实测无差异）
$FA       = 'on'           # -fa：flash-attn；KV 量化在 V 上必须开，且长上下文 prefill 明显更快
$NP       = 1              # -np：并行槽位；1 表示整个 -c 都给单个请求（DSH 是单请求串行，多槽位会切分上下文）

$server = Join-Path $LLAMA 'llama-server.exe'
foreach ($p in @($server, $MODEL, $MMPROJ)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "路径不存在：$p" }
}

Write-Host "启动 llama-server：ctx=$CTX ngl=$NGL kv=$KVK/$KVV fa=$FA np=$NP host=$HostAddr port=$Port"
if ($CTX -lt 38565) {
    Write-Host "注意：-CTX $CTX 低于实测最长请求 38565 tokens，超过该长度的请求会被 llama-server 以 exceed_context_size_error 拒绝。"
}
if ($HostAddr -eq '0.0.0.0') {
    Write-Host "注意：-HostAddr 0.0.0.0 表示监听所有网卡，局域网内其它机器可直接访问本服务；该服务没有鉴权，仅本机使用请用默认的 127.0.0.1。"
}

& $server `
    -m $MODEL `
    --mmproj $MMPROJ `
    -c $CTX `
    -ngl $NGL `
    -ctk $KVK `
    -ctv $KVV `
    -fa $FA `
    -np $NP `
    --host $HostAddr `
    --port $Port `
    --reasoning-budget $BUDGET
