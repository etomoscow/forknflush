<#
.SYNOPSIS
  forknflush installer for Windows (PowerShell).

.DESCRIPTION
  Clones the repo and creates skill symlinks/junctions for the chosen platform.

.EXAMPLE
  ./install.ps1                       # prompt for platform
  ./install.ps1 codex                 # install for codex
  ./install.ps1 -Update               # pull latest changes
  ./install.ps1 -Uninstall codex      # remove links for codex
#>

param(
    [Parameter(Position = 0)]
    [string]$Platform,
    [switch]$Update,
    [string]$Uninstall,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

$RepoUrl    = if ($env:FF_REPO_URL) { $env:FF_REPO_URL } else { 'https://github.com/etomoscow/forknflush.git' }
$RepoDir    = if ($env:FF_DIR)      { $env:FF_DIR }      else { Join-Path $HOME '.forknflush\repo' }
$PluginLink = Join-Path $HOME '.forknflush-plugin'

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
  install.ps1 [<platform>]                Install for <platform> (or prompt if omitted)
  install.ps1 -Update                     Pull latest changes
  install.ps1 -Uninstall <platform>       Remove links for <platform>
  install.ps1 -Help

Supported platforms:
$($Platforms.Keys -join ', ')

Environment:
  FF_REPO_URL  Override clone URL (default: official repo)
  FF_DIR       Override clone destination (default: $HOME\.forknflush\repo)
"@
}

function Resolve-Platform {
    param([string]$Id)
    if (-not $Platforms.Contains($Id)) {
        Write-Error "Unknown platform: $Id. Supported: $($Platforms.Keys -join ', ')"
    }
    return $Platforms[$Id]
}

function Prompt-Platform {
    $ids = @($Platforms.Keys)
    Write-Host 'Which platform are you installing for?' -ForegroundColor Cyan
    for ($i = 0; $i -lt $ids.Count; $i++) {
        Write-Host ("  {0}) {1}" -f ($i + 1), $ids[$i])
    }
    $choice = Read-Host "Choose [1-$($ids.Count)]"
    if (-not $choice -match '^\d+$' -or [int]$choice -lt 1 -or [int]$choice -gt $ids.Count) {
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

function New-DirLink {
    param([string]$LinkPath, [string]$TargetPath)
    if (Test-Path $LinkPath) { Remove-Item -Force -Recurse $LinkPath }
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
                    if ((Test-Path $link) -and (Get-Item $link -Force).LinkType) { Remove-Item -Force $link }
                }
            }
            else {
                # Checkout is gone — remove stale links pointing into our plugin tree.
                foreach ($link in (Get-ChildItem -Path $Target -Force -ErrorAction SilentlyContinue)) {
                    if ($link.LinkType -and $link.Target -and ($link.Target -like '*forknflush-plugin\skills*')) {
                        Remove-Item -Force $link.FullName
                    }
                }
            }
        }
        'folder' {
            $link = Join-Path $Target 'forknflush'
            if ((Test-Path $link) -and (Get-Item $link -Force).LinkType) { Remove-Item -Force $link }
        }
    }
}

function Invoke-Install {
    param([string]$Id)
    $cfg = Resolve-Platform $Id
    Update-Checkout
    Write-Host "→ Linking skills for $Id ($($cfg.Style) → $($cfg.Target))"
    Install-Skills -Target $cfg.Target -Style $cfg.Style
    Write-Host '→ Linking universal plugin root'
    if (Test-Path $PluginLink) {
        Write-Host "  • $PluginLink already exists, leaving as-is"
    }
    else {
        New-DirLink -LinkPath $PluginLink -TargetPath (Join-Path $RepoDir 'forknflush-plugin')
        Write-Host "  ✓ $PluginLink → $(Join-Path $RepoDir 'forknflush-plugin')"
    }
    Write-Host ""
    Write-Host "✓ Installed forknflush for $Id" -ForegroundColor Green
    Write-Host '  Restart your CLI to pick up the skills.'
    if ($Id -eq 'claude') {
        Write-Host ''
        Write-Host '  Tip: Claude Code can also install this repo directly as a plugin:'
        Write-Host '       /plugin marketplace add etomoscow/forknflush'
        Write-Host '       /plugin install forknflush'
    }
    if ($Id -eq 'codex') {
        Write-Host ''
        Write-Host '  Tip: Codex invokes skills with $ instead of / — type $fork-and-flush, not /fork-and-flush.'
    }
    if ($Id -eq 'pi') {
        Write-Host ''
        Write-Host '  Tip: Pi invokes skills with /skill:fork-and-flush.'
    }
    if ($Id -eq 'hermes') {
        Write-Host ''
        Write-Host '  Tip: project-local Hermes skills need `hermes skills trust`; ~/.hermes/skills loads unconditionally.'
    }
}

function Invoke-Uninstall {
    param([string]$Id)
    $cfg = Resolve-Platform $Id
    Write-Host "→ Removing skill links for $Id"
    Remove-Skills -Target $cfg.Target -Style $cfg.Style
    if ((Test-Path $PluginLink) -and (Get-Item $PluginLink -Force).LinkType) {
        Remove-Item -Force $PluginLink
        Write-Host "  ✓ removed $PluginLink"
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
    Invoke-Uninstall -Id $Uninstall
    exit 0
}

if (-not $Platform) {
    $Platform = Prompt-Platform
}

Invoke-Install -Id $Platform
