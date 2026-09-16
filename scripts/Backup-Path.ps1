<#
.SYNOPSIS
    Backs up System and User PATH environment variables to timestamped files.
.DESCRIPTION
    Saves current System and User PATH values to text files in the backup directory.
    Runs an audit of registry-installed apps and npm globals to flag missing PATH entries.
    Also prunes old backups beyond a configurable retention count.
.PARAMETER BackupDir
    Directory to store backups. Defaults to OneDrive\PATH_Backups.
.PARAMETER MaxBackups
    Maximum number of backup pairs to keep per scope. Oldest are removed. Default: 20.
.PARAMETER SkipAudit
    Skip the installed-apps audit step.
.EXAMPLE
    .\Backup-Path.ps1
    .\Backup-Path.ps1 -BackupDir "D:\Backups\PATH" -MaxBackups 10
    .\Backup-Path.ps1 -SkipAudit
#>
[CmdletBinding()]
param(
    [string]$BackupDir = (Join-Path ($env:OneDrive ?? $env:USERPROFILE) "PATH_Backups"),
    [int]$MaxBackups = 20,
    [switch]$SkipAudit
)

$ErrorActionPreference = 'Stop'

# ── Ensure backup directory exists ──────────────────────────────────────────
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Host "Created backup directory: $BackupDir" -ForegroundColor DarkGray
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# ── Backup System PATH ─────────────────────────────────────────────────────
$systemPath = [Environment]::GetEnvironmentVariable("Path", "Machine") ?? ''
$systemFile = Join-Path $BackupDir "SystemPath_$timestamp.txt"
$systemPath | Out-File $systemFile -Encoding UTF8

$systemEntries = ($systemPath -split ';' | Where-Object { $_ -ne '' }).Count
Write-Host "System PATH backed up: $systemFile ($systemEntries entries)" -ForegroundColor Green

# ── Backup User PATH ───────────────────────────────────────────────────────
$userPath = [Environment]::GetEnvironmentVariable("Path", "User") ?? ''
$userFile = Join-Path $BackupDir "UserPath_$timestamp.txt"
$userPath | Out-File $userFile -Encoding UTF8

$userEntries = ($userPath -split ';' | Where-Object { $_ -ne '' }).Count
Write-Host "User PATH backed up:   $userFile ($userEntries entries)" -ForegroundColor Green

# ── Prune old backups ──────────────────────────────────────────────────────
foreach ($prefix in @("SystemPath_", "UserPath_")) {
    $allBackups = Get-ChildItem $BackupDir -Filter "$prefix*.txt" | Sort-Object LastWriteTime -Descending
    if ($allBackups.Count -gt $MaxBackups) {
        $toRemove = $allBackups | Select-Object -Skip $MaxBackups
        foreach ($old in $toRemove) {
            Remove-Item $old.FullName -Force
            Write-Host "  Pruned old backup: $($old.Name)" -ForegroundColor DarkGray
        }
    }
}

# ── Summary ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Backup complete. Files in: $BackupDir" -ForegroundColor Cyan
$existing = Get-ChildItem $BackupDir -Filter "*.txt" | Sort-Object Name
Write-Host "  Total backup files: $($existing.Count)"

# ── Audit installed apps and npm globals ────────────────────────────────────
if (-not $SkipAudit) {
    Write-Host ""
    $auditScript = Join-Path $PSScriptRoot "Audit-PathApps.ps1"
    if (Test-Path $auditScript) {
        Write-Host "Running installed-apps PATH audit..." -ForegroundColor Cyan
        Write-Host ""
        $auditResults = & $auditScript
        if ($auditResults -and $auditResults.Count -gt 0) {
            $auditFile = Join-Path $BackupDir "Audit_$timestamp.txt"
            $auditResults | Format-Table -AutoSize | Out-String | Out-File $auditFile -Encoding UTF8
            Write-Host "  Audit report saved: $auditFile" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "Audit-PathApps.ps1 not found at: $auditScript — skipping audit." -ForegroundColor DarkGray
    }
}
