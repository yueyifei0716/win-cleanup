#Requires -Version 5.1
<#
.SYNOPSIS
    Windows disk & cache cleanup script with package manager maintenance.
.DESCRIPTION
    Cleans temp files, system caches, package manager caches, and optionally
    updates packages. Designed to run periodically via Task Scheduler.
.PARAMETER UpdatePackages
    Also run package manager updates (conda, pip, npm, scoop, winget).
.PARAMETER DryRun
    Show what would be cleaned without deleting anything.
.PARAMETER Force
    Skip confirmation prompt.
.EXAMPLE
    .\cleanup.ps1                  # Clean caches only
    .\cleanup.ps1 -UpdatePackages  # Clean caches + update packages
    .\cleanup.ps1 -DryRun          # Preview only
#>

param(
    [switch]$UpdatePackages,
    [switch]$DryRun,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

# ─── Config ──────────────────────────────────────────────────────────────
# Add paths here to always skip during cleanup
$ProtectedPaths = @(
    "$env:APPDATA\Claude\claude-code",        # Claude Code memory & config
    "$env:APPDATA\Claude\vm_bundles",          # Claude desktop runtime
    "$env:APPDATA\Claude\claude-code-vm"       # Claude Code VM
)

# ─── Helpers ─────────────────────────────────────────────────────────────

function Write-Header($text) {
    Write-Host "`n=== $text ===" -ForegroundColor Cyan
}

function Format-Size($bytes) {
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N0} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N0} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

function Get-DirSize($path) {
    if (-not (Test-Path $path)) { return 0 }
    (Get-ChildItem $path -Recurse -File -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
}

function Remove-SafeDir($path, $label) {
    if (-not (Test-Path $path)) { return 0 }
    # Skip protected paths
    foreach ($pp in $ProtectedPaths) {
        if ($path -like "$pp*") {
            Write-Host "  [SKIP] $label (protected)" -ForegroundColor Yellow
            return 0
        }
    }
    $size = Get-DirSize $path
    if ($size -lt 1KB) { return 0 }
    if ($DryRun) {
        Write-Host "  [DRY] $label : $(Format-Size $size)" -ForegroundColor DarkGray
    } else {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $path)) {
            Write-Host "  [OK]  $label : $(Format-Size $size)" -ForegroundColor Green
        } else {
            # Partial cleanup (some files locked)
            $remaining = Get-DirSize $path
            $cleaned = $size - $remaining
            if ($cleaned -gt 0) {
                Write-Host "  [PART] $label : $(Format-Size $cleaned) freed ($(Format-Size $remaining) locked)" -ForegroundColor Yellow
            }
        }
    }
    return $size
}

function Test-Command($name) {
    $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

# ─── Start ───────────────────────────────────────────────────────────────

$startTime = Get-Date
$totalCleaned = 0

$drive = Get-PSDrive C
$freeBefore = $drive.Free
Write-Host "Windows Disk & Cache Cleanup" -ForegroundColor White
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "Disk: $(Format-Size $drive.Used) used / $(Format-Size $drive.Free) free / $(Format-Size ($drive.Used + $drive.Free)) total"
if ($DryRun) { Write-Host "[DRY RUN MODE - no files will be deleted]" -ForegroundColor Yellow }

if (-not $Force -and -not $DryRun) {
    $confirm = Read-Host "`nProceed with cleanup? (y/N)"
    if ($confirm -ne 'y') {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# ─── 1. Windows Temp Files ──────────────────────────────────────────────

Write-Header "Windows Temp Files"
$totalCleaned += Remove-SafeDir "$env:TEMP\*" "User Temp"
if (-not $DryRun) { Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue }
$totalCleaned += Remove-SafeDir "C:\Windows\Temp\*" "System Temp"
if (-not $DryRun) { Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue }

# ─── 2. Windows System Caches ───────────────────────────────────────────

Write-Header "Windows System Caches"
$totalCleaned += Remove-SafeDir "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" "Thumbnail Cache"
$totalCleaned += Remove-SafeDir "C:\Windows\SoftwareDistribution\Download" "Windows Update Cache"
$totalCleaned += Remove-SafeDir "$env:LOCALAPPDATA\CrashDumps" "Crash Dumps"
$totalCleaned += Remove-SafeDir "C:\Windows\Prefetch" "Prefetch"

# Windows Installer temp
if (Test-Path "C:\Windows\Installer\$PatchCache$") {
    $totalCleaned += Remove-SafeDir "C:\Windows\Installer\`$PatchCache`$" "Installer Patch Cache"
}

# ─── 3. Browser Caches ──────────────────────────────────────────────────

Write-Header "Browser Caches"
$chromeCache = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
$totalCleaned += Remove-SafeDir $chromeCache "Chrome Cache"
$totalCleaned += Remove-SafeDir "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache" "Chrome Code Cache"
$totalCleaned += Remove-SafeDir "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Service Worker\CacheStorage" "Chrome SW Cache"

$edgeCache = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
$totalCleaned += Remove-SafeDir $edgeCache "Edge Cache"

# ─── 4. Application Caches ──────────────────────────────────────────────

Write-Header "Application Caches"

# Claude (only safe parts)
$totalCleaned += Remove-SafeDir "$env:APPDATA\Claude\Cache" "Claude Cache"
$totalCleaned += Remove-SafeDir "$env:APPDATA\Claude\Code Cache" "Claude Code Cache"
$totalCleaned += Remove-SafeDir "$env:APPDATA\Claude\GPUCache" "Claude GPU Cache"
$totalCleaned += Remove-SafeDir "$env:APPDATA\Claude\logs" "Claude Logs"
$totalCleaned += Remove-SafeDir "$env:APPDATA\Claude\local-agent-mode-sessions" "Claude Agent Sessions"

# NVIDIA
$totalCleaned += Remove-SafeDir "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache" "NVIDIA Shader Cache"
$totalCleaned += Remove-SafeDir "$env:APPDATA\NVIDIA" "NVIDIA Roaming Cache"

# Docker (temp only, not images/volumes)
$totalCleaned += Remove-SafeDir "$env:TEMP\DockerDesktop" "Docker Desktop Temp"

# Cursor / VS Code
$totalCleaned += Remove-SafeDir "$env:APPDATA\Cursor\Cache" "Cursor Cache"
$totalCleaned += Remove-SafeDir "$env:APPDATA\Cursor\CachedData" "Cursor Cached Data"
$totalCleaned += Remove-SafeDir "$env:APPDATA\Code\Cache" "VS Code Cache"
$totalCleaned += Remove-SafeDir "$env:APPDATA\Code\CachedData" "VS Code Cached Data"

# ─── 5. Package Manager Caches ──────────────────────────────────────────

Write-Header "Package Manager Caches"

# conda
if (Test-Command 'conda') {
    Write-Host "  Cleaning conda cache..."
    if (-not $DryRun) {
        conda clean --all --yes 2>&1 | Out-Null
        Write-Host "  [OK]  conda clean --all" -ForegroundColor Green
    } else {
        $condaPkgs = Get-DirSize "C:\ProgramData\miniconda3\pkgs"
        Write-Host "  [DRY] conda pkgs cache: $(Format-Size $condaPkgs)" -ForegroundColor DarkGray
    }
}

# pip
if (Test-Command 'pip') {
    Write-Host "  Cleaning pip cache..."
    if (-not $DryRun) {
        pip cache purge 2>&1 | Out-Null
        Write-Host "  [OK]  pip cache purge" -ForegroundColor Green
    } else {
        $pipCache = Get-DirSize "$env:LOCALAPPDATA\pip\cache"
        Write-Host "  [DRY] pip cache: $(Format-Size $pipCache)" -ForegroundColor DarkGray
    }
}

# uv
if (Test-Command 'uv') {
    Write-Host "  Cleaning uv cache..."
    if (-not $DryRun) {
        uv cache clean 2>&1 | Out-Null
        Write-Host "  [OK]  uv cache clean" -ForegroundColor Green
    } else {
        Write-Host "  [DRY] uv cache clean" -ForegroundColor DarkGray
    }
}

# npm
if (Test-Command 'npm') {
    Write-Host "  Cleaning npm cache..."
    if (-not $DryRun) {
        npm cache clean --force 2>&1 | Out-Null
        Write-Host "  [OK]  npm cache clean" -ForegroundColor Green
    } else {
        $npmCache = Get-DirSize "$env:LOCALAPPDATA\npm-cache"
        Write-Host "  [DRY] npm cache: $(Format-Size $npmCache)" -ForegroundColor DarkGray
    }
}

# pnpm
if (Test-Command 'pnpm') {
    Write-Host "  Cleaning pnpm store..."
    if (-not $DryRun) {
        pnpm store prune 2>&1 | Out-Null
        Write-Host "  [OK]  pnpm store prune" -ForegroundColor Green
    } else {
        Write-Host "  [DRY] pnpm store prune" -ForegroundColor DarkGray
    }
}

# yarn
if (Test-Command 'yarn') {
    Write-Host "  Cleaning yarn cache..."
    if (-not $DryRun) {
        yarn cache clean 2>&1 | Out-Null
        Write-Host "  [OK]  yarn cache clean" -ForegroundColor Green
    } else {
        Write-Host "  [DRY] yarn cache clean" -ForegroundColor DarkGray
    }
}

# bun
if (Test-Command 'bun') {
    $totalCleaned += Remove-SafeDir "$env:LOCALAPPDATA\bun\install\cache" "bun cache"
}

# cargo
if (Test-Command 'cargo') {
    $totalCleaned += Remove-SafeDir "$env:USERPROFILE\.cargo\registry\cache" "cargo registry cache"
}

# go
if (Test-Command 'go') {
    Write-Host "  Cleaning go module cache..."
    if (-not $DryRun) {
        go clean -modcache 2>&1 | Out-Null
        Write-Host "  [OK]  go clean -modcache" -ForegroundColor Green
    } else {
        $goCache = Get-DirSize "$env:USERPROFILE\go\pkg\mod\cache"
        Write-Host "  [DRY] go mod cache: $(Format-Size $goCache)" -ForegroundColor DarkGray
    }
}

# scoop
if (Test-Command 'scoop') {
    Write-Host "  Cleaning scoop cache..."
    if (-not $DryRun) {
        scoop cache rm * 2>&1 | Out-Null
        scoop cleanup * 2>&1 | Out-Null
        Write-Host "  [OK]  scoop cache rm + cleanup" -ForegroundColor Green
    } else {
        $scoopCache = Get-DirSize "$env:USERPROFILE\scoop\cache"
        Write-Host "  [DRY] scoop cache: $(Format-Size $scoopCache)" -ForegroundColor DarkGray
    }
}

# docker
if (Test-Command 'docker') {
    Write-Host "  Cleaning docker build cache & dangling images..."
    if (-not $DryRun) {
        docker system prune -f 2>&1 | Out-Null
        Write-Host "  [OK]  docker system prune" -ForegroundColor Green
    } else {
        Write-Host "  [DRY] docker system prune" -ForegroundColor DarkGray
    }
}

# ─── 6. Recycle Bin ─────────────────────────────────────────────────────

Write-Header "Recycle Bin"
if (-not $DryRun) {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK]  Recycle Bin emptied" -ForegroundColor Green
} else {
    Write-Host "  [DRY] Clear Recycle Bin" -ForegroundColor DarkGray
}

# ─── 7. Package Updates (optional) ──────────────────────────────────────

if ($UpdatePackages) {
    Write-Header "Package Updates"

    if (Test-Command 'conda') {
        Write-Host "  Updating conda..."
        conda update conda -y 2>&1 | Select-Object -Last 3
        conda update --all -y 2>&1 | Select-Object -Last 3
        Write-Host "  [OK]  conda updated" -ForegroundColor Green
    }

    if (Test-Command 'pip') {
        Write-Host "  Updating pip..."
        pip install --upgrade pip 2>&1 | Select-Object -Last 1
        # Update all outdated packages
        $outdated = pip list --outdated --format=json 2>$null | ConvertFrom-Json
        if ($outdated.Count -gt 0) {
            $names = ($outdated | ForEach-Object { $_.name }) -join ' '
            Write-Host "  Updating $($outdated.Count) pip packages..."
            pip install --upgrade $names.Split(' ') 2>&1 | Select-Object -Last 1
        }
        Write-Host "  [OK]  pip updated" -ForegroundColor Green
    }

    if (Test-Command 'npm') {
        Write-Host "  Updating npm global packages..."
        npm update -g 2>&1 | Select-Object -Last 3
        Write-Host "  [OK]  npm globals updated" -ForegroundColor Green
    }

    if (Test-Command 'scoop') {
        Write-Host "  Updating scoop packages..."
        scoop update * 2>&1 | Select-Object -Last 5
        Write-Host "  [OK]  scoop updated" -ForegroundColor Green
    }

    if (Test-Command 'winget') {
        Write-Host "  Updating winget dev tool packages..."
        # Only update whitelisted dev tools, not games/entertainment
        $wingetDevPkgs = @(
            'Git.Git', 'Microsoft.VisualStudioCode', 'Microsoft.WindowsTerminal',
            'Docker.DockerDesktop', 'Python.Python.3', 'OpenJS.NodeJS',
            'Google.Chrome', 'Mozilla.Firefox', 'Notepad++.Notepad++',
            'JetBrains.Toolbox', 'Microsoft.PowerShell', 'GoLang.Go',
            'Rustlang.Rust.MSVC', 'Postman.Postman'
        )
        foreach ($pkg in $wingetDevPkgs) {
            winget upgrade --id $pkg --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        }
        Write-Host "" # blank line after winget output
        Write-Host "  [OK]  winget updated" -ForegroundColor Green
    }
}

# ─── Summary ─────────────────────────────────────────────────────────────

Write-Header "Summary"
$drive = Get-PSDrive C
$freeAfter = $drive.Free
$freed = $freeAfter - $freeBefore
$elapsed = (Get-Date) - $startTime

Write-Host "Disk now: $(Format-Size $drive.Used) used / $(Format-Size $drive.Free) free"
if ($freed -gt 0) {
    Write-Host "Freed:   $(Format-Size $freed)" -ForegroundColor Green
}
Write-Host "Time:    $($elapsed.Minutes)m $($elapsed.Seconds)s"
Write-Host ""
