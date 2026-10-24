<#
  Qwen3.5-9B 多模态本地推理服务启动脚本（llama.cpp / llama-server）。

  下面的 -c / -ngl 是**基线参数，部署后需实测调优**的结果：当前值来自本机实测
  （RTX 5070 Ti Laptop，12227 MiB，llama.cpp build 11853，CUDA 13.4 构建），
  换机器、换驱动或换量化后需要重新实测，方法见同目录 model-notes.md 的「复现步骤」。

  监听默认 127.0.0.1:8090：本机 127.0.0.1:8080 已被 Steam 的 steamwebhelper 占用（实测该端口上的
  请求会打到 Steam 而不是模型），所以默认端口避开 8080、改用 8090；同时默认只绑回环地址，
  不把没有鉴权的推理服务暴露到局域网。需要局域网访问时显式传 -HostAddr 0.0.0.0，
  注意此时同网段任何机器都能调用本服务且没有鉴权。详见 model-notes.md「端口冲突」一节。
#>
param(
    [string]$HostAddr = '127.0.0.1', # --host：默认只绑回环地址，仅本机可用；需要局域网访问时显式传 -HostAddr 0.0.0.0（服务无鉴权）
    [int]$Port = 8090                # --port：默认 8090，避开被 Steam 占用的 127.0.0.1:8080；端口被占用时改这里即可
)

$ErrorActionPreference = 'Stop'

# ---- 路径：集中定义，只改这里 ----
$LLAMA  = 'G:\LocalAI\tools\llama.cpp'                              # llama-server.exe 与 CUDA 运行库所在目录
$MODEL  = 'G:\LocalAI\models\Qwen3.5-9B\Qwen3.5-9B-Q4_K_M.gguf'    # 主模型（Q4_K_M）
$MMPROJ = 'G:\LocalAI\models\Qwen3.5-9B\mmproj-F16.gguf'           # 视觉投影器（F16）

# ---- 运行时参数：必须与 model-notes.md 的「实测最优值」一致 ----
$CTX      = 16384          # -c：上下文长度（实测最优；32768 也能跑，但显存逼近上限、解码降至约 4.6 tok/s）
$NGL      = 99             # -ngl：卸载到 GPU 的层数（99 = 全部层；实测最优）
$BUDGET   = 0              # --reasoning-budget：0 表示不输出思考链

$server = Join-Path $LLAMA 'llama-server.exe'
foreach ($p in @($server, $MODEL, $MMPROJ)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "路径不存在：$p" }
}

Write-Host "启动 llama-server：ctx=$CTX ngl=$NGL host=$HostAddr port=$Port"
if ($HostAddr -eq '0.0.0.0') {
    Write-Host "注意：-HostAddr 0.0.0.0 表示监听所有网卡，局域网内其它机器可直接访问本服务；该服务没有鉴权，仅本机使用请用默认的 127.0.0.1。"
}

& $server `
    -m $MODEL `
    --mmproj $MMPROJ `
    -c $CTX `
    -ngl $NGL `
    --host $HostAddr `
    --port $Port `
    --reasoning-budget $BUDGET
