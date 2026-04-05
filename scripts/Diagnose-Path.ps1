<#
.SYNOPSIS
    Diagnoses System and User PATH environment variables for common issues.
.DESCRIPTION
    Checks for: duplicates within each PATH, cross-duplicates between System/User,
    non-existent directories, and empty entries. If issues are found, offers to
    restore from a backup via Restore-Path.ps1.
.PARAMETER AutoRestore
    If set, automatically invokes Restore-Path.ps1 when issues are found (no prompt).
.EXAMPLE
    .\Diagnose-Path.ps1
    .\Diagnose-Path.ps1 -AutoRestore
#>
param(
    [switch]$AutoRestore
)

$ErrorActionPreference = 'Stop'

function Get-PathEntries {
    param([string]$Scope)
    $raw = [Environment]::GetEnvironmentVariable("Path", $Scope)
    if (-not $raw) { return @() }
    return ($raw -split ';' | Where-Object { $_ -ne '' })
}

function Normalize {
    param([string]$Entry)
    return $Entry.TrimEnd('\').ToLower()
}

# ── Gather entries ──────────────────────────────────────────────────────────
$systemEntries = Get-PathEntries -Scope "Machine"
$userEntries = Get-PathEntries -Scope "User"

$issues = @()
$issueCount = 0

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  PATH Diagnostic Report" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "System PATH: $($systemEntries.Count) entries"
Write-Host "User PATH:   $($userEntries.Count) entries"
Write-Host ""

# ── 1. Empty entries ────────────────────────────────────────────────────────
Write-Host "--- Empty Entries ---" -ForegroundColor Yellow
$sRaw = ([Environment]::GetEnvironmentVariable("Path", "Machine")) -split ';'
$uRaw = ([Environment]::GetEnvironmentVariable("Path", "User")) -split ';'
$sEmpties = ($sRaw | Where-Object { $_.Trim() -eq '' }).Count
$uEmpties = ($uRaw | Where-Object { $_.Trim() -eq '' }).Count
if ($sEmpties -gt 0) {
    Write-Host "  System: $sEmpties empty entries" -ForegroundColor Red
    $issueCount += $sEmpties
    $issues += "System PATH has $sEmpties empty entries"
}
if ($uEmpties -gt 0) {
    Write-Host "  User: $uEmpties empty entries" -ForegroundColor Red
    $issueCount += $uEmpties
    $issues += "User PATH has $uEmpties empty entries"
}
if ($sEmpties -eq 0 -and $uEmpties -eq 0) {
    Write-Host "  None" -ForegroundColor Green
}
Write-Host ""

# ── 2. Duplicates within System PATH ───────────────────────────────────────
Write-Host "--- System PATH Internal Duplicates ---" -ForegroundColor Yellow
$sNorm = $systemEntries | ForEach-Object { Normalize $_ }
$sGrouped = $sNorm | Group-Object | Where-Object { $_.Count -gt 1 }
if ($sGrouped) {
    foreach ($g in $sGrouped) {
        Write-Host "  DUP: $($g.Name) (x$($g.Count))" -ForegroundColor Red
        $issueCount++
        $issues += "System duplicate: $($g.Name)"
    }
}
else {
    Write-Host "  None" -ForegroundColor Green
}
Write-Host ""

# ── 3. Duplicates within User PATH ─────────────────────────────────────────
Write-Host "--- User PATH Internal Duplicates ---" -ForegroundColor Yellow
$uNorm = $userEntries | ForEach-Object { Normalize $_ }
$uGrouped = $uNorm | Group-Object | Where-Object { $_.Count -gt 1 }
if ($uGrouped) {
    foreach ($g in $uGrouped) {
        Write-Host "  DUP: $($g.Name) (x$($g.Count))" -ForegroundColor Red
        $issueCount++
        $issues += "User duplicate: $($g.Name)"
    }
}
else {
    Write-Host "  None" -ForegroundColor Green
}
Write-Host ""

# ── 4. Cross-duplicates (User entries already in System) ───────────────────
Write-Host "--- Cross-Duplicates (User entries already in System PATH) ---" -ForegroundColor Yellow
$sNormSet = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]($systemEntries | ForEach-Object { Normalize $_ }),
    [System.StringComparer]::OrdinalIgnoreCase
)
$crossDupes = @()
foreach ($entry in $userEntries) {
    $norm = Normalize $entry
    if ($sNormSet.Contains($norm)) {
        $crossDupes += $entry
    }
}
if ($crossDupes.Count -gt 0) {
    foreach ($d in $crossDupes) {
        Write-Host "  CROSS-DUP: $d" -ForegroundColor Red
    }
    $issueCount += $crossDupes.Count
    $issues += "$($crossDupes.Count) User PATH entries duplicate System PATH"
}
else {
    Write-Host "  None" -ForegroundColor Green
}
Write-Host ""

# ── 5. Non-existent paths ──────────────────────────────────────────────────
Write-Host "--- Non-Existent Paths (System) ---" -ForegroundColor Yellow
$sMissing = @()
foreach ($e in $systemEntries) {
    if (-not (Test-Path $e)) { $sMissing += $e; Write-Host "  MISSING: $e" -ForegroundColor Red }
}
if ($sMissing.Count -eq 0) { Write-Host "  None" -ForegroundColor Green }
$issueCount += $sMissing.Count
if ($sMissing.Count -gt 0) { $issues += "$($sMissing.Count) missing System PATH entries" }
Write-Host ""

Write-Host "--- Non-Existent Paths (User) ---" -ForegroundColor Yellow
$uMissing = @()
foreach ($e in $userEntries) {
    if (-not (Test-Path $e)) { $uMissing += $e; Write-Host "  MISSING: $e" -ForegroundColor Red }
}
if ($uMissing.Count -eq 0) { Write-Host "  None" -ForegroundColor Green }
$issueCount += $uMissing.Count
if ($uMissing.Count -gt 0) { $issues += "$($uMissing.Count) missing User PATH entries" }
Write-Host ""

# ── 6. Well-known tool reachability ─────────────────────────────────────────
Write-Host "--- Well-Known Tool Reachability ---" -ForegroundColor Yellow
$toolChecks = @(
    @{ Name = "winget"; Hint = "`$env:LOCALAPPDATA\Microsoft\WindowsApps" }
    @{ Name = "git"; Hint = "C:\Program Files\Git\cmd" }
    @{ Name = "node"; Hint = "C:\Program Files\nodejs" }
    @{ Name = "python"; Hint = "Python install directory" }
    @{ Name = "dotnet"; Hint = "C:\Program Files\dotnet" }
    @{ Name = "code"; Hint = "`$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin" }
    @{ Name = "pwsh"; Hint = "C:\Program Files\PowerShell\7" }
    @{ Name = "choco"; Hint = "C:\ProgramData\chocolatey\bin" }
)
$toolMissing = 0
foreach ($tool in $toolChecks) {
    $found = Get-Command $tool.Name -ErrorAction SilentlyContinue
    if ($found) {
        Write-Host "  OK: $($tool.Name) -> $($found.Source)" -ForegroundColor Green
    }
    else {
        Write-Host "  MISSING: $($tool.Name) — expected in: $($tool.Hint)" -ForegroundColor Red
        $toolMissing++
    }
}
if ($toolMissing -gt 0) {
    $issueCount += $toolMissing
    $issues += "$toolMissing well-known tool(s) not reachable via PATH"
}
Write-Host ""

# ── Summary ─────────────────────────────────────────────────────────────────
Write-Host "============================================" -ForegroundColor Cyan
if ($issueCount -eq 0) {
    Write-Host "  No issues found. PATH is clean." -ForegroundColor Green
}
else {
    Write-Host "  $issueCount issue(s) found:" -ForegroundColor Red
    foreach ($i in $issues) {
        Write-Host "    - $i" -ForegroundColor Red
    }
}
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ── Sync session PATH from registry ─────────────────────────────────────────
$registryPath = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
if ($env:Path -ne $registryPath) {
    $env:Path = $registryPath
    Write-Host "Session PATH was out of sync with registry — refreshed." -ForegroundColor Yellow
    Write-Host ""
}

# ── Offer restore if issues found ──────────────────────────────────────────
if ($issueCount -gt 0) {
    $restoreScript = Join-Path $PSScriptRoot "Restore-Path.ps1"
    if (-not (Test-Path $restoreScript)) {
        Write-Warning "Restore-Path.ps1 not found at: $restoreScript"
        return
    }


    if ($AutoRestore) {
        Write-Host "AutoRestore enabled — launching Restore-Path.ps1..." -ForegroundColor Yellow
        & $restoreScript
    }
    else {
        $response = Read-Host "Issues detected. Restore from backup? (y/n)"
        if ($response -eq 'y') {
            & $restoreScript
        }
        else {
            Write-Host "No changes made."
        }
    }
}
