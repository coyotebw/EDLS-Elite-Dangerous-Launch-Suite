#Requires -Version 5.1
<#
.SYNOPSIS
    One-time setup: configures git to use the committed hooks in .githooks/.
.DESCRIPTION
    Run this once after cloning the repository.
    It sets core.hooksPath to .githooks so GitHub Desktop and the git CLI
    automatically trigger the post-merge hook on every pull — which rebuilds
    EliteLaunchSuite.exe without any manual PSEBuilder step.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
$HookFile = Join-Path $RepoRoot '.githooks' 'post-merge'

Write-Host ""
Write-Host "=== EDLaunchSuite Setup ===" -ForegroundColor Cyan
Write-Host ""

# ── Configure git hooksPath ────────────────────────────────────────────────────
Write-Host "Configuring git core.hooksPath -> .githooks" -ForegroundColor Yellow

Push-Location $RepoRoot
try {
    git config core.hooksPath .githooks
    Write-Host "git config set." -ForegroundColor Green
} finally {
    Pop-Location
}

# ── Ensure the hook file is executable ────────────────────────────────────────
# chmod works in WSL / Git Bash; on native Windows it's a no-op but harmless.
if (Get-Command chmod -ErrorAction SilentlyContinue) {
    chmod +x $HookFile
    Write-Host "Execute permission set on post-merge hook." -ForegroundColor Green
} else {
    Write-Host "Note: chmod not available here. If the hook doesn't auto-trigger," -ForegroundColor Yellow
    Write-Host "  run this once in Git Bash:" -ForegroundColor Yellow
    Write-Host "  git update-index --chmod=+x .githooks/post-merge" -ForegroundColor Gray
}

# ── Offer an immediate build ───────────────────────────────────────────────────
Write-Host ""
$RunNow = Read-Host "Run Build.ps1 now to produce EliteLaunchSuite.exe? [Y/N]"
if ($RunNow -match '^[Yy]') {
    & (Join-Path $RepoRoot 'Build.ps1')
} else {
    Write-Host "Skipped. Run .\Build.ps1 any time to build manually." -ForegroundColor Gray
}

Write-Host ""
Write-Host "Setup complete. Future 'git pull' operations will rebuild automatically." -ForegroundColor Green
Write-Host ""
