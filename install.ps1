<#
.SYNOPSIS
  forknflush installer for Windows (PowerShell).

.DESCRIPTION
  Clones the repo and creates skill symlinks/junctions for the chosen platform(s).

.EXAMPLE
  ./install.ps1                       # prompt for platform
  ./install.ps1 codex                 # install for codex
  ./install.ps1 all                   # install for all platforms
  ./install.ps1 -Update               # pull latest changes
  ./install.ps1 -Uninstall codex      # remove links for codex
#>

param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Platform,
    [switch]$Update,
    [string]$Uninstall,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

$RepoUrl = if ($env:FF_REPO_URL) { $env:FF_REPO_URL } else { 'https://github.com/etomoscow/forknflush.git' }
$RepoDir = if ($env:FF_DIR)      { $env:FF_DIR }      else { Join-Path $HOME '.forknflush\repo' }

# Platform table - Target = skills directory; Style = "per-skill" | "folder"
$Platforms = [ordered]@{
    claude   = @{ Target = (Join-Path $HOME '.claude\skills');  Style = 'per-skill' }
    pi       = @{ Target = (Join-Path $HOME '.agents\skills');  Style = 'per-skill' }
    codex    = @{ Target = (Join-Path $HOME '.agents\skills');  Style = 'per-skill' }
    opencode = @{ Target = (Join-Path $HOME '.agents\skills');  Style = 'per-skill' }
    hermes   = @{ Target = (Join-Path $HOME '.hermes\skills');  Style = 'folder' }
}

function Show-Usage {
    @"
forknflush installer (Windows)

Usage:
  install.ps1 [<platform>...]             Install for platform(s) or 'all' (prompts if omitted)
  install.ps1 -Update                     Pull latest changes
  install.ps1 -Uninstall <platform>       Remove links for <platform> or 'all'
  install.ps1 -Help

Supported platforms:
$($Platforms.Keys -join ', '), all

Environment:
  FF_REPO_URL  Override clone URL (default: official repo)
  FF_DIR       Override clone destination (default: $HOME\.forknflush\repo)
"@
}

function Resolve-Platform {
    param([string]$Id)
    if (-not $Platforms.Contains($Id)) {
        Write-Error "Unknown platform: $Id. Supported: $($Platforms.Keys -join ', '), all"
    }
    return $Platforms[$Id]
}

function Expand-Platforms {
    param([string[]]$Ids)
    $result = @()
    foreach ($id in $Ids) {
        if ($id -eq 'all') {
            $result += $Platforms.Keys
        }
        else {
            $null = Resolve-Platform $id
            $result += $id
        }
    }
    return $result
}

function Prompt-Platform {
    $ids = @($Platforms.Keys) + @('all')
    Write-Host 'Which platform are you installing for?' -ForegroundColor Cyan
    for ($i = 0; $i -lt $ids.Count; $i++) {
        Write-Host ("  {0}) {1}" -f ($i + 1), $ids[$i])
    }
    $choice = Read-Host "Choose [1-$($ids.Count)]"
    if (-not ($choice -match '^\d+$') -or [int]$choice -lt 1 -or [int]$choice -gt $ids.Count) {
        Write-Error "Invalid choice: '$choice'. Pass the platform as an argument instead, e.g.: install.ps1 codex"
    }
    return $ids[[int]$choice - 1]
}

function Update-Checkout {
    if (Test-Path (Join-Path $RepoDir '.git')) {
        Write-Host "→ Updating existing checkout at $RepoDir"
        git -C $RepoDir pull --ff-only
        if ($LASTEXITCODE -ne 0) { Write-Error 'git pull failed' }
    }
    else {
        Write-Host "→ Cloning $RepoUrl → $RepoDir"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $RepoDir) | Out-Null
        git clone $RepoUrl $RepoDir
        if ($LASTEXITCODE -ne 0) { Write-Error 'git clone failed' }
    }
}

function Get-SkillsRoot { Join-Path $RepoDir 'forknflush-plugin\skills' }

function Get-Skills {
    param([string]$Root)
    if (-not (Test-Path $Root)) { Write-Error "Skills directory not found: $Root" }
    Get-ChildItem -Path $Root -Directory | ForEach-Object { $_.Name }
}

function Remove-SafeLink {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    $item = Get-Item $Path -Force
    if ($item.LinkType) {
        # Delete the reparse point itself without recursing into its target.
        $item.Delete()
    }
    else {
        Write-Error "Refusing to overwrite non-link directory: $Path"
    }
}

function New-DirLink {
    param([string]$LinkPath, [string]$TargetPath)
    if (Test-Path $LinkPath) { Remove-SafeLink -Path $LinkPath }
    $parent = Split-Path -Parent $LinkPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    try {
        New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath | Out-Null
    }
    catch {
        # Symlinks need developer mode / admin on Windows — fall back to a junction.
        New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath | Out-Null
    }
}

function Install-Skills {
    param([string]$Target, [string]$Style)
    $root = Get-SkillsRoot
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    switch ($Style) {
        'per-skill' {
            foreach ($skill in (Get-Skills $root)) {
                New-DirLink -LinkPath (Join-Path $Target $skill) -TargetPath (Join-Path $root $skill)
                Write-Host "  ✓ $(Join-Path $Target $skill) → $(Join-Path $root $skill)"
            }
        }
        'folder' {
            New-DirLink -LinkPath (Join-Path $Target 'forknflush') -TargetPath $root
            Write-Host "  ✓ $(Join-Path $Target 'forknflush') → $root"
        }
        default { Write-Error "Unknown style: $Style" }
    }
}

function Remove-Skills {
    param([string]$Target, [string]$Style)
    if (-not (Test-Path $Target)) { return }
    switch ($Style) {
        'per-skill' {
            if (Test-Path (Get-SkillsRoot)) {
                foreach ($skill in (Get-Skills (Get-SkillsRoot))) {
                    $link = Join-Path $Target $skill
                    if ((Test-Path $link) -and (Get-Item $link -Force).LinkType) {
                        (Get-Item $link -Force).Delete()
                    }
                }
            }
            else {
                foreach ($link in (Get-ChildItem -Path $Target -Force -ErrorAction SilentlyContinue)) {
                    if ($link.LinkType -and $link.Target -and ($link.Target -like '*forknflush-plugin\skills*')) {
                        $link.Delete()
                    }
                }
            }
        }
        'folder' {
            $link = Join-Path $Target 'forknflush'
            if ((Test-Path $link) -and (Get-Item $link -Force).LinkType) {
                (Get-Item $link -Force).Delete()
            }
        }
    }
}

function Invoke-Install {
    param([string[]]$Ids)
    $resolved = Expand-Platforms $Ids
    Update-Checkout
    foreach ($id in $resolved) {
        $cfg = Resolve-Platform $id
        Write-Host "→ Linking skills for $id ($($cfg.Style) → $($cfg.Target))"
        Install-Skills -Target $cfg.Target -Style $cfg.Style
    }
    Write-Host ""
    Write-Host "✓ Installed forknflush ($($resolved -join ', ')). Restart your CLI to pick up the skill." -ForegroundColor Green
}

function Invoke-Uninstall {
    param([string[]]$Ids)
    $resolved = Expand-Platforms $Ids
    foreach ($id in $resolved) {
        $cfg = Resolve-Platform $id
        Write-Host "→ Removing skill links for $id"
        Remove-Skills -Target $cfg.Target -Style $cfg.Style
    }
    if (Test-Path $RepoDir) {
        Write-Host ""
        Write-Host "The checkout at $RepoDir was kept (other platforms may still use it)."
        Write-Host "To remove it: Remove-Item -Recurse -Force `"$RepoDir`""
    }
}

if ($Help) { Show-Usage; exit 0 }

if ($Update) {
    if (-not (Test-Path (Join-Path $RepoDir '.git'))) {
        Write-Error "No installation found at $RepoDir. Run install first."
    }
    git -C $RepoDir pull --ff-only
    if ($LASTEXITCODE -ne 0) { Write-Error 'git pull failed' }
    Write-Host '✓ Updated.' -ForegroundColor Green
    exit 0
}

if ($Uninstall) {
    Invoke-Uninstall -Ids @($Uninstall)
    exit 0
}

if (-not $Platform -or $Platform.Count -eq 0) {
    $Platform = @(Prompt-Platform)
}

Invoke-Install -Ids $Platform
