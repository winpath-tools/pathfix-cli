<#
.SYNOPSIS
    Restores System and/or User PATH from backup files.
.DESCRIPTION
    Lists available PATH backups from the backup directory, lets the user pick
    which backup to restore, and applies it. Requires elevation for System PATH.
.PARAMETER BackupDir
    Directory containing backup files. Defaults to OneDrive\PATH_Backups.
.PARAMETER Scope
    Which PATH to restore: System, User, or Both. Defaults to prompting.
.EXAMPLE
    .\Restore-Path.ps1
    .\Restore-Path.ps1 -BackupDir "D:\Backups\PATH" -Scope User
#>
[CmdletBinding()]
param(
    [string]$BackupDir = (Join-Path ($env:OneDrive ?? $env:USERPROFILE) "PATH_Backups"),
    [ValidateSet("System", "User", "Both", "")]
    [string]$Scope = ""
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $BackupDir)) {
    Write-Error "Backup directory not found: $BackupDir"
    return
}

# ── List available backups ──────────────────────────────────────────────────
$systemBackups = Get-ChildItem $BackupDir -Filter "SystemPath_*.txt" | Sort-Object LastWriteTime -Descending
$userBackups = Get-ChildItem $BackupDir -Filter "UserPath_*.txt"   | Sort-Object LastWriteTime -Descending

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  PATH Restore Utility" -ForegroundColor Cyan
Write-Host "  Backup dir: $BackupDir" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if ($systemBackups.Count -eq 0 -and $userBackups.Count -eq 0) {
    Write-Warning "No backup files found in $BackupDir"
    return
}

# ── Determine scope ────────────────────────────────────────────────────────
if (-not $Scope) {
    Write-Host "What would you like to restore?"
    Write-Host "  [1] System PATH"
    Write-Host "  [2] User PATH"
    Write-Host "  [3] Both"
    Write-Host "  [Q] Quit"
    $choice = Read-Host "Selection"
    switch ($choice) {
        '1' { $Scope = "System" }
        '2' { $Scope = "User" }
        '3' { $Scope = "Both" }
        default { Write-Host "Cancelled."; return }
    }
}

function Restore-PathFromBackup {
    param(
        [string]$PathScope,
        [System.IO.FileInfo[]]$Backups
    )

    if ($Backups.Count -eq 0) {
        Write-Warning "No $PathScope PATH backups found."
        return $false
    }

    Write-Host ""
    Write-Host "Available $PathScope PATH backups:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $Backups.Count; $i++) {
        $size = "{0:N0}" -f $Backups[$i].Length
        Write-Host ("  [{0}] {1}  ({2} bytes, {3})" -f ($i + 1), $Backups[$i].Name, $size, $Backups[$i].LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
    }
    Write-Host "  [Q] Skip"

    $pick = Read-Host "Select backup to restore for $PathScope PATH"
    if ($pick -eq 'Q' -or $pick -eq 'q') {
        Write-Host "Skipped $PathScope PATH restore."
        return $false
    }

    $parsedIndex = 0
    $index = if ([int]::TryParse($pick, [ref]$parsedIndex)) { $parsedIndex - 1 } else { -1 }
    if ($index -lt 0 -or $index -ge $Backups.Count) {
        Write-Warning "Invalid selection."
        return $false
    }

    $selectedFile = $Backups[$index]
    $newPath = (Get-Content $selectedFile.FullName -Raw).Trim()

    if ([string]::IsNullOrWhiteSpace($newPath)) {
        Write-Error "Backup file is empty: $($selectedFile.FullName)"
        return $false
    }

    $entryCount = ($newPath -split ';' | Where-Object { $_ -ne '' }).Count
    Write-Host ""
    Write-Host "Restoring $PathScope PATH from: $($selectedFile.Name)" -ForegroundColor Yellow
    Write-Host "  Entries: $entryCount"
    Write-Host "  Preview (first 5):"
    ($newPath -split ';' | Where-Object { $_ -ne '' } | Select-Object -First 5) | ForEach-Object { Write-Host "    $_" }
    Write-Host ""

    $confirm = Read-Host "Apply this $PathScope PATH? (y/n)"
    if ($confirm -ne 'y') {
        Write-Host "Skipped."
        return $false
    }

    # Check admin for System scope
    $target = if ($PathScope -eq "System") { "Machine" } else { "User" }
    if ($PathScope -eq "System") {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Error "Restoring System PATH requires running as Administrator."
            return $false
        }
    }

    # Auto-backup current before overwriting
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $currentPath = [Environment]::GetEnvironmentVariable("Path", $target)
    $autoBackupName = "${PathScope}Path_PRE-RESTORE_$timestamp.txt"
    $currentPath | Out-File (Join-Path $BackupDir $autoBackupName) -Encoding UTF8
    Write-Host "  Auto-backup of current $PathScope PATH saved as: $autoBackupName" -ForegroundColor DarkGray

    [Environment]::SetEnvironmentVariable("Path", $newPath, $target)
    Write-Host "  $PathScope PATH restored successfully." -ForegroundColor Green
    return $true
}

# ── Execute restores ───────────────────────────────────────────────────────
$anyRestored = $false
if ($Scope -eq "System" -or $Scope -eq "Both") {
    if (Restore-PathFromBackup -PathScope "System" -Backups $systemBackups) { $anyRestored = $true }
}

if ($Scope -eq "User" -or $Scope -eq "Both") {
    if (Restore-PathFromBackup -PathScope "User" -Backups $userBackups) { $anyRestored = $true }
}

# ── Refresh current session PATH from registry ─────────────────────────────
if ($anyRestored) {
    $env:Path = ([Environment]::GetEnvironmentVariable("Path", "Machine") ?? '') + ";" + ([Environment]::GetEnvironmentVariable("Path", "User") ?? '')

    Write-Host ""
    Write-Host "Restore complete. This session's PATH has been refreshed." -ForegroundColor Cyan
    Write-Host "Other open terminals still need to be restarted or run:" -ForegroundColor DarkGray
    Write-Host '  $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")' -ForegroundColor DarkGray
} else {
    Write-Host ""
    Write-Host "No changes were applied." -ForegroundColor DarkGray
}
