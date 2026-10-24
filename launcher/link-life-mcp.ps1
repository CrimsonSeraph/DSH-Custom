# link-life-mcp.ps1
# 把生活型 Agent 的 MCP server 定义（custom\life-agent\mcp\mcp.servers.json）
# 合并进指定 DSH profile 的 cordis.patch.yml。
#
# 规则：缺失才补。目标 profile（以及 DSH 根级 cordis.patch.yml）里已存在的
# 同名 server 一律跳过，绝不覆盖自用配置；改写前先备份，改写后自检 YAML 结构。
#
# 用法：
#   .\link-life-mcp.ps1 -DryRun                      # 预演：只打印计划，不落盘
#   .\link-life-mcp.ps1 -Profile web                 # 真实合并到 profile web
#   .\link-life-mcp.ps1 -Profile web -LifeMcp .\my.json
#
# 参数：
#   -Profile  DSH profile 名（默认 desktop），对应 <DSH 目录>\profiles\<Profile>
#   -LifeMcp  生活型 MCP 定义文件；省略时推断为脚本所在 custom\ 下的
#             life-agent\mcp\mcp.servers.json
#   -DryRun   预演开关：打印将新增的 YAML 与备份路径，不创建备份、不写文件
#
# DSH 目录取 $env:DSH_HOME，未设置时用 <用户主目录>\.dsh。
param(
  [string]$Profile = 'desktop',
  [string]$LifeMcp = '',
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$LF = [string][char]10

function Write-Info {
  param([string]$Message)
  Write-Host ('[life-mcp] ' + $Message)
}

function Fail {
  param([string]$Message)
  Write-Host ('[life-mcp] 错误：' + $Message)
  exit 1
}

# ---------------------------------------------------------------------------
# 最小 YAML 子集解析器（仅用于自检，不参与写出）
# 支持：块映射 / 块序列 / 单双引号标量 / 空流式集合 [] 与 {} / 注释。
# 遇到块标量、锚点别名、非空流式集合等超出子集的结构时抛错，由调用方决定跳过。
# ---------------------------------------------------------------------------
$script:yamlNodes = $null
$script:yamlIndex = 0
$script:yamlRoot = $null

function Remove-YamlComment {
  param([string]$Text)
  $inSingle = $false
  $inDouble = $false
  for ($i = 0; $i -lt $Text.Length; $i++) {
    $c = $Text[$i]
    if ($inSingle) {
      if ($c -eq "'") {
        if ((($i + 1) -lt $Text.Length) -and ($Text[$i + 1] -eq "'")) { $i++ } else { $inSingle = $false }
      }
      continue
    }
    if ($inDouble) {
      if ($c -eq '\') { $i++ } elseif ($c -eq '"') { $inDouble = $false }
      continue
    }
    if ($c -eq "'") { $inSingle = $true; continue }
    if ($c -eq '"') { $inDouble = $true; continue }
    if ($c -eq '#') {
      if (($i -eq 0) -or ($Text[$i - 1] -eq ' ') -or ($Text[$i - 1] -eq [char]9)) { return $Text.Substring(0, $i) }
    }
  }
  return $Text
}

function ConvertFrom-YamlScalar {
  param([string]$Text)
  $t = Remove-YamlComment $Text
  $t = $t.Trim()
  if ($t -eq '') { return $null }
  if ($t -eq '[]') { return ,(New-Object System.Collections.ArrayList) }
  if ($t -eq '{}') { return [ordered]@{} }
  $first = $t[0]
  if ($first -eq '"') {
    if (($t.Length -lt 2) -or ($t[$t.Length - 1] -ne '"')) { throw ('双引号字符串未闭合：' + $t) }
    $inner = $t.Substring(1, $t.Length - 2)
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $inner.Length; $i++) {
      $c = $inner[$i]
      if ($c -eq '\') {
        $i++
        if ($i -ge $inner.Length) { throw ('双引号字符串转义不完整：' + $t) }
        $e = $inner[$i]
        if ($e -eq 'n') { [void]$sb.Append([char]10) }
        elseif ($e -eq 't') { [void]$sb.Append([char]9) }
        elseif ($e -eq 'r') { [void]$sb.Append([char]13) }
        elseif ($e -eq '"') { [void]$sb.Append('"') }
        elseif ($e -eq '\') { [void]$sb.Append('\') }
        else { throw ('不支持的双引号转义：\' + $e) }
      } else { [void]$sb.Append($c) }
    }
    return $sb.ToString()
  }
  if ($first -eq "'") {
    if (($t.Length -lt 2) -or ($t[$t.Length - 1] -ne "'")) { throw ('单引号字符串未闭合：' + $t) }
    return $t.Substring(1, $t.Length - 2).Replace("''", "'")
  }
  if (($first -eq '[') -or ($first -eq '{')) { throw ('不支持非空流式集合：' + $t) }
  if (($first -eq '|') -or ($first -eq '>')) { throw ('不支持块标量：' + $t) }
  if (($first -eq '&') -or ($first -eq '*') -or ($first -eq '!')) { throw ('不支持锚点/别名/标签：' + $t) }
  if ($t -eq 'true') { return $true }
  if ($t -eq 'false') { return $false }
  if (($t -eq 'null') -or ($t -eq '~')) { return $null }
  if ($t -match '^-?[0-9]+$') { return [long]$t }
  return $t
}

function Split-YamlKeyValue {
  param([string]$Text)
  $t = $Text.Trim()
  if ($t -eq '') { return $null }
  $inSingle = $false
  $inDouble = $false
  for ($i = 0; $i -lt $t.Length; $i++) {
    $c = $t[$i]
    if ($inSingle) {
      if ($c -eq "'") {
        if ((($i + 1) -lt $t.Length) -and ($t[$i + 1] -eq "'")) { $i++ } else { $inSingle = $false }
      }
      continue
    }
    if ($inDouble) {
      if ($c -eq '\') { $i++ } elseif ($c -eq '"') { $inDouble = $false }
      continue
    }
    if ($c -eq "'") { $inSingle = $true; continue }
    if ($c -eq '"') { $inDouble = $true; continue }
    if ($c -eq ':') {
      $isLast = ($i -eq ($t.Length - 1))
      $next = [char]0
      if (-not $isLast) { $next = $t[$i + 1] }
      if ($isLast -or ($next -eq ' ') -or ($next -eq [char]9)) {
        $keyText = $t.Substring(0, $i).Trim()
        $valueText = ''
        if (-not $isLast) { $valueText = $t.Substring($i + 1).Trim() }
        $key = $keyText
        if (($keyText.Length -ge 2) -and (($keyText[0] -eq '"') -or ($keyText[0] -eq "'"))) {
          $key = [string](ConvertFrom-YamlScalar $keyText)
        }
        if ($key -eq '') { return $null }
        return @{ Key = $key; Value = $valueText }
      }
    }
  }
  return $null
}

function Add-YamlMapEntry {
  param($Map, [string]$Key, [string]$ValueText, [int]$KeyIndent, [int]$Line)
  if ($Map.Contains($Key)) { throw ('同一映射内键重复（第 ' + $Line + ' 行）：' + $Key) }
  if ($ValueText.Trim() -eq '') {
    if (($script:yamlIndex -lt $script:yamlNodes.Count) -and ($script:yamlNodes[$script:yamlIndex].Indent -gt $KeyIndent)) {
      $node = $script:yamlNodes[$script:yamlIndex]
      if ($node.IsSeq) {
        $childList = New-Object System.Collections.ArrayList
        $Map[$Key] = $childList
        Read-YamlSeq -List $childList -Indent $node.Indent
      } else {
        $childMap = [ordered]@{}
        $Map[$Key] = $childMap
        Read-YamlMap -Map $childMap -Indent $node.Indent
      }
    } else {
      $Map[$Key] = $null
    }
  } else {
    $Map[$Key] = ConvertFrom-YamlScalar $ValueText
  }
}

function Read-YamlSeq {
  param($List, [int]$Indent)
  while ($script:yamlIndex -lt $script:yamlNodes.Count) {
    $node = $script:yamlNodes[$script:yamlIndex]
    if ((-not $node.IsSeq) -or ($node.Indent -ne $Indent)) { break }
    $script:yamlIndex++
    if ($node.Text -eq '') {
      if (($script:yamlIndex -lt $script:yamlNodes.Count) -and ($script:yamlNodes[$script:yamlIndex].Indent -gt $Indent)) {
        $childNode = $script:yamlNodes[$script:yamlIndex]
        if ($childNode.IsSeq) {
          $childList = New-Object System.Collections.ArrayList
          [void]$List.Add($childList)
          Read-YamlSeq -List $childList -Indent $childNode.Indent
        } else {
          $childMap = [ordered]@{}
          [void]$List.Add($childMap)
          Read-YamlMap -Map $childMap -Indent $childNode.Indent
        }
      } else {
        [void]$List.Add($null)
      }
      continue
    }
    $kv = Split-YamlKeyValue $node.Text
    if ($null -eq $kv) {
      [void]$List.Add((ConvertFrom-YamlScalar $node.Text))
      continue
    }
    $virtualIndent = $Indent + 2
    $itemMap = [ordered]@{}
    Add-YamlMapEntry -Map $itemMap -Key $kv.Key -ValueText $kv.Value -KeyIndent $virtualIndent -Line $node.Line
    while ($script:yamlIndex -lt $script:yamlNodes.Count) {
      $next = $script:yamlNodes[$script:yamlIndex]
      if ($next.IsSeq -or ($next.Indent -ne $virtualIndent)) { break }
      $script:yamlIndex++
      $kv2 = Split-YamlKeyValue $next.Text
      if ($null -eq $kv2) { throw ('无法解析的键值行（第 ' + $next.Line + ' 行）：' + $next.Text) }
      Add-YamlMapEntry -Map $itemMap -Key $kv2.Key -ValueText $kv2.Value -KeyIndent $virtualIndent -Line $next.Line
    }
    [void]$List.Add($itemMap)
  }
}

function Read-YamlMap {
  param($Map, [int]$Indent)
  while ($script:yamlIndex -lt $script:yamlNodes.Count) {
    $node = $script:yamlNodes[$script:yamlIndex]
    if ($node.IsSeq -or ($node.Indent -ne $Indent)) { break }
    $script:yamlIndex++
    $kv = Split-YamlKeyValue $node.Text
    if ($null -eq $kv) { throw ('无法解析的映射行（第 ' + $node.Line + ' 行）：' + $node.Text) }
    Add-YamlMapEntry -Map $Map -Key $kv.Key -ValueText $kv.Value -KeyIndent $Indent -Line $node.Line
  }
}

function ConvertFrom-SimpleYaml {
  param([string[]]$Lines)
  $script:yamlNodes = New-Object System.Collections.ArrayList
  $script:yamlRoot = $null
  $lineNo = 0
  foreach ($raw in $Lines) {
    $lineNo++
    $r = $raw
    if ($null -eq $r) { continue }
    $r = $r.TrimEnd([char]13, [char]10)
    if ($r.Trim() -eq '') { continue }
    if ($r.TrimStart().StartsWith('#')) { continue }
    if (($r.Trim() -eq '---') -or ($r.Trim() -eq '...')) { continue }
    $indent = ([regex]::Match($r, '^[ ]*')).Length
    $body = $r.Substring($indent)
    if ($body.StartsWith([char]9)) { throw ('不支持制表符缩进（第 ' + $lineNo + ' 行）') }
    if ($body -eq '-') {
      [void]$script:yamlNodes.Add([pscustomobject]@{ Indent = $indent; IsSeq = $true; Text = ''; Line = $lineNo })
    } elseif ($body.StartsWith('- ')) {
      [void]$script:yamlNodes.Add([pscustomobject]@{ Indent = $indent; IsSeq = $true; Text = $body.Substring(2).Trim(); Line = $lineNo })
    } else {
      [void]$script:yamlNodes.Add([pscustomobject]@{ Indent = $indent; IsSeq = $false; Text = $body; Line = $lineNo })
    }
  }
  if ($script:yamlNodes.Count -eq 0) {
    $script:yamlRoot = New-Object System.Collections.ArrayList
    return
  }
  $script:yamlIndex = 0
  $first = $script:yamlNodes[0]
  if ($first.IsSeq) {
    $rootList = New-Object System.Collections.ArrayList
    $script:yamlRoot = $rootList
    Read-YamlSeq -List $rootList -Indent $first.Indent
  } else {
    $rootMap = [ordered]@{}
    $script:yamlRoot = $rootMap
    Read-YamlMap -Map $rootMap -Indent $first.Indent
  }
  if ($script:yamlIndex -lt $script:yamlNodes.Count) {
    $left = $script:yamlNodes[$script:yamlIndex]
    throw ('无法解析的结构（第 ' + $left.Line + ' 行）：' + $left.Text)
  }
}

# ---------------------------------------------------------------------------
# YAML 输出
# ---------------------------------------------------------------------------
function Format-YamlScalar {
  param($Value)
  if ($Value -is [bool]) {
    if ($Value) { return 'true' }
    return 'false'
  }
  if (($Value -is [int]) -or ($Value -is [long])) { return ([string]$Value) }
  $s = [string]$Value
  if ($s -match '[\r\n]') { throw ('取值含换行，无法写成 YAML 标量：' + $s) }
  return ("'" + $s.Replace("'", "''") + "'")
}

function Format-YamlKey {
  param([string]$Key)
  if ($Key -match '^[A-Za-z_][A-Za-z0-9_.-]*$') { return $Key }
  throw ('键名含特殊字符，拒绝写出：' + $Key)
}

function Add-EntryYamlLines {
  param($Entry, $Lines)
  [void]$Lines.Add('- insert:')
  [void]$Lines.Add('    - id: ' + (Format-YamlScalar $Entry.Id))
  [void]$Lines.Add('      name: ' + (Format-YamlScalar '@deepseek-ai/dsh-mcp-client'))
  if ($Entry.Disabled) { [void]$Lines.Add('      disabled: true') }
  [void]$Lines.Add('      config:')
  foreach ($k in $Entry.Config.Keys) {
    $v = $Entry.Config[$k]
    if ($null -eq $v) { continue }
    if ($v -is [System.Collections.IDictionary]) {
      if ($v.Count -eq 0) {
        [void]$Lines.Add('        ' + (Format-YamlKey $k) + ': {}')
        continue
      }
      [void]$Lines.Add('        ' + (Format-YamlKey $k) + ':')
      foreach ($kk in $v.Keys) {
        [void]$Lines.Add('          ' + (Format-YamlKey $kk) + ': ' + (Format-YamlScalar $v[$kk]))
      }
    } elseif (($v -is [System.Collections.ArrayList]) -or ($v -is [object[]])) {
      if ($v.Count -eq 0) {
        [void]$Lines.Add('        ' + (Format-YamlKey $k) + ': []')
      } else {
        [void]$Lines.Add('        ' + (Format-YamlKey $k) + ':')
        foreach ($item in $v) { [void]$Lines.Add('          - ' + (Format-YamlScalar $item)) }
      }
    } else {
      [void]$Lines.Add('        ' + (Format-YamlKey $k) + ': ' + (Format-YamlScalar $v))
    }
  }
}

# ---------------------------------------------------------------------------
# 路径解析
# ---------------------------------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$customDir = Split-Path -Parent $scriptDir
if ($LifeMcp -eq '') { $LifeMcp = Join-Path $customDir 'life-agent\mcp\mcp.servers.json' }
$LifeMcp = [System.IO.Path]::GetFullPath($LifeMcp)

$dshHome = $env:DSH_HOME
if ((-not $dshHome) -or ($dshHome -eq '')) {
  $userHome = $env:USERPROFILE
  if ((-not $userHome) -or ($userHome -eq '')) { $userHome = [Environment]::GetFolderPath('UserProfile') }
  $dshHome = Join-Path $userHome '.dsh'
}
$dshHome = [System.IO.Path]::GetFullPath($dshHome)

Write-Info ('DSH 目录：' + $dshHome)
Write-Info ('生活型 MCP 定义：' + $LifeMcp)

if (-not (Test-Path -LiteralPath $dshHome -PathType Container)) { Fail ('DSH 目录不存在：' + $dshHome) }
if ($Profile -notmatch '^[A-Za-z0-9._-]+$') { Fail ('profile 名非法（只允许字母、数字、点、下划线、连字符）：' + $Profile) }

$profileDir = Join-Path $dshHome ('profiles\' + $Profile)
if (-not (Test-Path -LiteralPath $profileDir -PathType Container)) {
  Fail ('profile 目录不存在：' + $profileDir + '。本脚本不会自动创建 profile；请确认 -Profile 名称，或先让 dsh 创建该 profile。')
}

$patchPath = Join-Path $profileDir 'cordis.patch.yml'
$cordisPath = Join-Path $profileDir 'cordis.yml'
$rootPatchPath = Join-Path $dshHome 'cordis.patch.yml'
$patchExists = Test-Path -LiteralPath $patchPath -PathType Leaf

Write-Info ('目标 profile：' + $Profile + '（' + $profileDir + '）')
Write-Info ('目标文件：' + $patchPath + $(if ($patchExists) { '（已存在，将追加）' } else { '（不存在，将新建）' }))

# ---------------------------------------------------------------------------
# 读取生活型 server 定义
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $LifeMcp -PathType Leaf)) { Fail ('生活型 MCP 定义文件不存在：' + $LifeMcp) }
try {
  $json = Get-Content -LiteralPath $LifeMcp -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
  Fail ('生活型 MCP 定义不是合法 JSON：' + $LifeMcp + ' / ' + $_.Exception.Message)
}
$serversProp = $json.PSObject.Properties['servers']
if ($null -eq $serversProp) { Fail ('生活型 MCP 定义缺少 servers 字段：' + $LifeMcp) }

$allowedKeys = @('serverName', 'transport', 'command', 'args', 'env', 'cwd', 'url', 'headers', 'failOnStartupError', 'id', 'disabled')
$plan = New-Object System.Collections.ArrayList

foreach ($prop in $serversProp.Value.PSObject.Properties) {
  $name = $prop.Name
  if ($name -notmatch '^[A-Za-z0-9_-]{1,32}$') { Fail ('server 名不满足 dsh-mcp-client 约束 [A-Za-z0-9_-]{1,32}：' + $name) }
  $def = $prop.Value
  if ($def -isnot [System.Management.Automation.PSCustomObject]) { Fail ('server 定义必须是 JSON 对象：' + $name) }

  $unknown = @()
  foreach ($kp in $def.PSObject.Properties) { if ($allowedKeys -notcontains $kp.Name) { $unknown += $kp.Name } }
  if ($unknown.Count -gt 0) { Fail ('server ' + $name + ' 含未知字段：' + ($unknown -join ', ') + '（允许：' + ($allowedKeys -join ', ') + '）') }

  if ($def.PSObject.Properties['serverName']) {
    if ([string]$def.PSObject.Properties['serverName'].Value -ne $name) {
      Fail ('server ' + $name + ' 的 serverName 与键名不一致：' + [string]$def.PSObject.Properties['serverName'].Value)
    }
  }

  $transport = ''
  if ($def.PSObject.Properties['transport']) { $transport = [string]$def.PSObject.Properties['transport'].Value }
  if (@('stdio', 'streamable-http') -notcontains $transport) {
    Fail ('server ' + $name + ' 的 transport 必须是 stdio 或 streamable-http，实际：' + $transport)
  }

  $cfg = [ordered]@{}
  $cfg['serverName'] = $name
  $cfg['transport'] = $transport

  if ($transport -eq 'stdio') {
    foreach ($forbidden in @('url', 'headers')) {
      if ($def.PSObject.Properties[$forbidden]) { Fail ('stdio server 不接受 ' + $forbidden + '：' + $name) }
    }
    if (-not $def.PSObject.Properties['command']) { Fail ('stdio server 缺少 command：' + $name) }
    $cfg['command'] = [string]$def.PSObject.Properties['command'].Value
    if ($def.PSObject.Properties['args']) {
      $argList = New-Object System.Collections.ArrayList
      foreach ($a in @($def.PSObject.Properties['args'].Value)) {
        if ($a -is [System.Management.Automation.PSCustomObject]) { Fail ('server ' + $name + ' 的 args 必须是字符串数组') }
        [void]$argList.Add([string]$a)
      }
      $cfg['args'] = $argList
    }
    if ($def.PSObject.Properties['env']) {
      $envMap = [ordered]@{}
      foreach ($ep in $def.PSObject.Properties['env'].Value.PSObject.Properties) { $envMap[$ep.Name] = [string]$ep.Value }
      $cfg['env'] = $envMap
    }
    if ($def.PSObject.Properties['cwd']) { $cfg['cwd'] = [string]$def.PSObject.Properties['cwd'].Value }
  } else {
    foreach ($forbidden in @('command', 'args', 'env', 'cwd')) {
      if ($def.PSObject.Properties[$forbidden]) { Fail ('streamable-http server 不接受 ' + $forbidden + '：' + $name) }
    }
    if (-not $def.PSObject.Properties['url']) { Fail ('streamable-http server 缺少 url：' + $name) }
    $cfg['url'] = [string]$def.PSObject.Properties['url'].Value
    if ($def.PSObject.Properties['headers']) {
      $headerMap = [ordered]@{}
      foreach ($hp in $def.PSObject.Properties['headers'].Value.PSObject.Properties) { $headerMap[$hp.Name] = [string]$hp.Value }
      $cfg['headers'] = $headerMap
    }
  }
  if ($def.PSObject.Properties['failOnStartupError']) { $cfg['failOnStartupError'] = [bool]$def.PSObject.Properties['failOnStartupError'].Value }

  $entryId = 'mcp-' + $name
  if ($def.PSObject.Properties['id']) { $entryId = [string]$def.PSObject.Properties['id'].Value }
  if ($entryId -notmatch '^[A-Za-z0-9_-]+$') { Fail ('server ' + $name + ' 的条目 id 非法：' + $entryId) }
  $disabled = $false
  if ($def.PSObject.Properties['disabled']) { $disabled = [bool]$def.PSObject.Properties['disabled'].Value }

  [void]$plan.Add([pscustomobject]@{ Name = $name; Id = $entryId; Disabled = $disabled; Config = $cfg })
}

Write-Info ('生活型 server 定义数：' + $plan.Count)

# ---------------------------------------------------------------------------
# 已注册 server 探测（同名即跳过，绝不覆盖）
# ---------------------------------------------------------------------------
$script:existing = [ordered]@{}

function Add-DetectedServer {
  param([string]$Name, [string]$Source)
  if (-not $script:existing.Contains($Name)) { $script:existing[$Name] = New-Object System.Collections.ArrayList }
  if (-not ($script:existing[$Name] -contains $Source)) { [void]$script:existing[$Name].Add($Source) }
}

$scanFiles = New-Object System.Collections.ArrayList
if (Test-Path -LiteralPath $rootPatchPath -PathType Leaf) { [void]$scanFiles.Add($rootPatchPath) }
if (Test-Path -LiteralPath $cordisPath -PathType Leaf) { [void]$scanFiles.Add($cordisPath) }
if ($patchExists) { [void]$scanFiles.Add($patchPath) }

foreach ($file in $scanFiles) {
  $text = [System.IO.File]::ReadAllText($file)
  foreach ($m in [regex]::Matches($text, 'serverName\s*:\s*[''"]?([A-Za-z0-9_-]+)')) { Add-DetectedServer -Name $m.Groups[1].Value -Source $file }
  foreach ($m in [regex]::Matches($text, 'mcp__([A-Za-z0-9_-]+?)__')) { Add-DetectedServer -Name $m.Groups[1].Value -Source $file }
  foreach ($m in [regex]::Matches($text, 'id\s*:\s*[''"]?mcp-([A-Za-z0-9_-]+)')) { Add-DetectedServer -Name $m.Groups[1].Value -Source $file }
}

$toAdd = New-Object System.Collections.ArrayList
$skipped = New-Object System.Collections.ArrayList
foreach ($entry in $plan) {
  if ($script:existing.Contains($entry.Name)) {
    [void]$skipped.Add($entry)
  } else {
    [void]$toAdd.Add($entry)
  }
}

if ($script:existing.Count -gt 0) {
  Write-Info '已注册的 server（探测来源）：'
  foreach ($k in $script:existing.Keys) {
    Write-Info ('  ' + $k + ' <- ' + ($script:existing[$k] -join ' , '))
  }
}

$skippedNames = @()
foreach ($s in $skipped) { $skippedNames += $s.Name }
$addedNames = @()
foreach ($a in $toAdd) { $addedNames += $a.Name }

if ($skipped.Count -gt 0) {
  Write-Info ('跳过同名 server（' + $skipped.Count + ' 个，已存在，不覆盖）：' + ($skippedNames -join ', '))
}

if ($toAdd.Count -eq 0) {
  Write-Info '没有需要新增的 server：生活型定义中的 server 全部已注册。未写文件。'
  exit 0
}

Write-Info ('新增 server（' + $toAdd.Count + ' 个）：' + ($addedNames -join ', '))

# ---------------------------------------------------------------------------
# 组装追加块
# ---------------------------------------------------------------------------
$blockLines = New-Object System.Collections.ArrayList
foreach ($entry in $toAdd) {
  [void]$blockLines.Add('')
  [void]$blockLines.Add('# --- ' + $entry.Name + '（生活型 Agent，缺失补齐；同名自用配置不会被覆盖）---')
  Add-EntryYamlLines -Entry $entry -Lines $blockLines
}

Write-Info '将追加的 YAML 片段：'
foreach ($l in $blockLines) { Write-Host ('  ' + $l) }

# ---------------------------------------------------------------------------
# 读取目标文件（保留 BOM 与换行风格）
# ---------------------------------------------------------------------------
$newline = $LF
$oldText = ''
$hasBom = $false
if ($patchExists) {
  $bytes = [System.IO.File]::ReadAllBytes($patchPath)
  if (($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)) { $hasBom = $true }
  $strict = New-Object System.Text.UTF8Encoding($false, $true)
  try { $decoded = $strict.GetString($bytes) } catch { Fail ('目标文件不是合法 UTF-8，拒绝改写：' + $patchPath) }
  if ($hasBom) { $decoded = $decoded.Substring(1) }
  $oldText = $decoded
  if ($oldText.Contains([string][char]13 + [string][char]10)) { $newline = [string][char]13 + [string][char]10 }
}

$blockText = ($blockLines -join $newline) + $newline
if ($oldText.Length -eq 0) {
  $newText = $blockText
  if ($newText.StartsWith($newline)) { $newText = $newText.Substring($newline.Length) }
} elseif ($oldText.EndsWith([string][char]10)) {
  $newText = $oldText + $blockText
} else {
  $newText = $oldText + $newline + $blockText
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = $null
if ($patchExists) {
  $backupPath = $patchPath + '.bak-life-mcp-' + $stamp
  $suffix = 1
  while (Test-Path -LiteralPath $backupPath) {
    $suffix++
    $backupPath = $patchPath + '.bak-life-mcp-' + $stamp + '-' + $suffix
  }
}

if ($DryRun) {
  Write-Info '[预演] 未写任何文件。'
  if ($patchExists) { Write-Info ('[预演] 真实执行时会先备份为：' + $backupPath) } else { Write-Info ('[预演] 真实执行时会新建：' + $patchPath) }
  exit 0
}

if ($patchExists) {
  Copy-Item -LiteralPath $patchPath -Destination $backupPath -Force
  Write-Info ('已备份：' + $backupPath)
}

$encoding = New-Object System.Text.UTF8Encoding($hasBom)
[System.IO.File]::WriteAllText($patchPath, $newText, $encoding)
Write-Info ('已写入：' + $patchPath)

# ---------------------------------------------------------------------------
# 写后自检
# ---------------------------------------------------------------------------
$problems = New-Object System.Collections.ArrayList
$afterText = [System.IO.File]::ReadAllText($patchPath, (New-Object System.Text.UTF8Encoding($false)))

if (($oldText.Length -gt 0) -and (-not $afterText.StartsWith($oldText))) {
  [void]$problems.Add('追加结果不再以原文件内容开头，可能发生了替换')
}

$oldParseable = $true
if ($oldText.Length -gt 0) {
  try {
    ConvertFrom-SimpleYaml -Lines ($oldText -split ([string][char]10))
  } catch {
    $oldParseable = $false
  }
}

$checkNames = New-Object System.Collections.ArrayList
$checkIds = New-Object System.Collections.ArrayList
$parseTarget = $null
$parseMode = ''
if ($oldParseable) {
  $parseTarget = $afterText
  $parseMode = '整文件'
} else {
  $parseTarget = $blockText
  $parseMode = '仅新增块（原文件含本自检器不支持的结构）'
}

if ($null -ne $parseTarget) {
  try {
    ConvertFrom-SimpleYaml -Lines ($parseTarget -split ([string][char]10))
    $root = $script:yamlRoot
    if (($root -is [System.Collections.IDictionary]) -or ($root -is [string])) {
      [void]$problems.Add('解析结果不是条目序列')
    } else {
      foreach ($item in $root) {
        if (-not ($item -is [System.Collections.IDictionary])) { continue }
        if (-not $item.Contains('insert')) { continue }
        $ins = $item['insert']
        if (($null -eq $ins) -or ($ins -is [string]) -or (-not ($ins -is [System.Collections.IEnumerable]))) { continue }
        foreach ($sub in $ins) {
          if (-not ($sub -is [System.Collections.IDictionary])) { continue }
          if ($sub.Contains('id')) { [void]$checkIds.Add([string]$sub['id']) }
          if ($sub.Contains('config')) {
            $subCfg = $sub['config']
            if (($subCfg -is [System.Collections.IDictionary]) -and $subCfg.Contains('serverName')) {
              [void]$checkNames.Add([string]$subCfg['serverName'])
            }
          }
        }
      }
      foreach ($entry in $toAdd) {
        if (-not ($checkNames -contains $entry.Name)) { [void]$problems.Add('自检解析结果缺少 serverName：' + $entry.Name) }
        if (-not ($checkIds -contains $entry.Id)) { [void]$problems.Add('自检解析结果缺少条目 id：' + $entry.Id) }
      }
    }
  } catch {
    [void]$problems.Add('YAML 解析失败：' + $_.Exception.Message)
  }
}

if ($problems.Count -gt 0) {
  foreach ($p in $problems) { Write-Host ('[life-mcp] 自检失败：' + $p) }
  if ($patchExists -and $backupPath -and (Test-Path -LiteralPath $backupPath)) {
    Copy-Item -LiteralPath $backupPath -Destination $patchPath -Force
    Write-Info ('已回滚为备份：' + $backupPath)
  } else {
    Remove-Item -LiteralPath $patchPath -Force
    Write-Info '已删除本次新建的文件。'
  }
  exit 1
}

Write-Info ('自检通过（' + $parseMode + '解析、原内容前缀、新增条目均在位）：' + ($addedNames -join ', '))
Write-Info ('完成：新增 ' + $toAdd.Count + ' 个，跳过 ' + $skipped.Count + ' 个同名 server。')
if ($backupPath) { Write-Info ('备份文件：' + $backupPath) }
