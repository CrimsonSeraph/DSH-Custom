# link-skills.ps1
# Symlink each skill folder under <AppDir>\.agents\skills and <AppDir>\custom\skills
# into <UserProfile>\.dsh\skills as a Junction.
# - Junctions do not require admin rights (local volumes only).
# - Existing correct links are skipped; links pointing elsewhere are refreshed;
#   real (non-link) directories with the same name are left untouched (warning).
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
  Write-Host "[skills] Created: $targetRoot"
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
    Write-Host "[skills] Skip (source missing): $src"
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
        Write-Host "[skills] Conflict (real dir exists, skipping): $linkPath"
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
        return  # already linked correctly
      }

      # Do NOT use Remove-Item -Recurse here: PS 5.1 would follow the junction
      # and delete the actual source content.
      Write-Host "[skills] Refreshing link: $skillName"
      [System.IO.Directory]::Delete($linkPath, $false)
    }

    New-Item -ItemType Junction -Path $linkPath -Target $skillSrc | Out-Null
    Write-Host "[skills] Linked: $skillName -> $skillSrc"
    $script:created++
  }
}

Write-Host "[skills] Done (created/refreshed: $created, conflicts: $conflicts)."
