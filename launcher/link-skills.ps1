# link-skills.ps1
# 把 <AppDir>\.agents\skills 与 <AppDir>\custom\skills 下的每个技能子目录
# 以 Junction 形式链接到 <User>\.dsh\skills\ 下。
# - 使用 Junction（不需要管理员权限，仅限本地卷）。
# - 已存在的正确链接会跳过；指向别处的链接会被刷新；
#   同名真实目录不会被覆盖，仅输出警告。
param(
  [Parameter(Mandatory = $true)]
  [string]$AppDir
)

$ErrorActionPreference = 'Stop'

$userProfile = $env:USERPROFILE
if (-not $userProfile) {
  $userProfile = [Environment]::GetFolderPath('UserProfile')
}
$targetRoot = Join-Path $userProfile '.dsh\skills'

if (-not (Test-Path -LiteralPath $targetRoot)) {
  New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
  Write-Host "[skills] 已创建目录: $targetRoot"
}

$sourceDirs = @(
  (Join-Path $AppDir '.agents\skills'),
  (Join-Path $AppDir 'custom\skills')
)

function Get-NormalizedPath {
  param([string]$Path)
  if (-not $Path) { return $null }
  $p = $Path -replace '^\\\\\?\\', ''
  try { return [System.IO.Path]::GetFullPath($p).TrimEnd('\') }
  catch { return $p.TrimEnd('\') }
}

$created   = 0
$conflicts = 0

foreach ($src in $sourceDirs) {
  if (-not (Test-Path -LiteralPath $src -PathType Container)) {
    Write-Host "[skills] 跳过（源目录不存在）: $src"
    continue
  }

  Get-ChildItem -LiteralPath $src -Directory -Force | ForEach-Object {
    $skillName = $_.Name
    $skillSrc  = Get-NormalizedPath $_.FullName
    $linkPath  = Join-Path $targetRoot $skillName

    if (Test-Path -LiteralPath $linkPath) {
      $existing = Get-Item -LiteralPath $linkPath -Force
      $isLink = [bool]($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint)

      if (-not $isLink) {
        Write-Host "[skills] 冲突（同名实体已存在，非链接，跳过）: $linkPath"
        $script:conflicts++
        return
      }

      $existingTarget = $null
      try {
        $t = $existing.Target
        if ($t -is [array]) { $t = $t[0] }
        $existingTarget = Get-NormalizedPath $t
      } catch { }

      if ($existingTarget -and ($existingTarget -ieq $skillSrc)) {
        return  # 已正确链接
      }

      # 注意：不要用 Remove-Item -Recurse，PS 5.1 会跟着 junction 删掉源内容。
      Write-Host "[skills] 刷新链接: $skillName"
      [System.IO.Directory]::Delete($linkPath, $false)
    }

    New-Item -ItemType Junction -Path $linkPath -Target $skillSrc | Out-Null
    Write-Host "[skills] 已链接: $skillName -> $skillSrc"
    $script:created++
  }
}

Write-Host "[skills] 完成（新建/刷新 $created，冲突 $conflicts）。"
