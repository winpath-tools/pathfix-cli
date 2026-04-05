<#
.SYNOPSIS
    Audits installed applications and npm globals for missing PATH entries.
.DESCRIPTION
    Scans the Windows registry uninstall keys and npm global prefix for CLI tools
    that have executables but are not reachable via the current PATH. Returns
    results as objects for piping, or displays a formatted report.
.PARAMETER SkipRegistry
    Skip the registry scan (only check npm globals).
.PARAMETER SkipNpm
    Skip the npm global scan (only check registry).
.PARAMETER Quiet
    Suppress console output; only return objects.
.EXAMPLE
    .\Audit-PathApps.ps1
    .\Audit-PathApps.ps1 -SkipRegistry
    $missing = .\Audit-PathApps.ps1 -Quiet
#>
[CmdletBinding()]
param(
    [switch]$SkipRegistry,
    [switch]$SkipNpm,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Write-Report {
    param([string]$Message, [string]$Color = "White")
    if (-not $Quiet) { Write-Host $Message -ForegroundColor $Color }
}

$currentPathEntries = $env:Path -split ';' | Where-Object { $_ -ne '' } | ForEach-Object { $_.TrimEnd('\').ToLower() }
$results = @()

# ── Filter: apps that don't need PATH entries ───────────────────────────────
$ignorePatterns = @(
    # Games and game launchers
    '*SteamLibrary*', '*steamapps*', '*BattlenetLibrary*',
    '*Battle.net*', '*Rockstar Games*', '*EA Library*',
    # Anti-cheat / DRM
    '*AntiCheat*', '*Anti-Cheat*', '*Denuvo*',
    # GPU drivers / helpers
    '*NVIDIA*NvContainer*', '*NVIDIA*Installer*', '*NVIDIA*ShadowPlay*', '*NVIDIA*FrameView*',
    # Browsers and desktop apps (GUI-only, launched via Start Menu / pinned)
    '*Google\Chrome*', '*Microsoft\Edge*', '*Microsoft\Copilot*',
    '*Discord*', '*Google\Drive*',
    '*Sony\PlayStation*', '*Battlelog*',
    # GUI-only desktop apps that don't benefit from PATH
    '*GitHubDesktop*', '*gitkraken*',
    '*HWiNFO*', '*CPUID*', '*HWMonitor*',
    '*PowerToys*',
    '*Everything*'
)

function Test-ShouldIgnore {
    param([string]$Path)
    foreach ($pattern in $ignorePatterns) {
        if ($Path -like $pattern) { return $true }
    }
    return $false
}

function Test-OnPath {
    param([string]$Dir)
    $norm = $Dir.TrimEnd('\').ToLower()
    return ($currentPathEntries -contains $norm)
}

# ── 1. Registry scan ───────────────────────────────────────────────────────
if (-not $SkipRegistry) {
    Write-Report "--- Registry Installed Apps ---" Yellow

    $regKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $apps = foreach ($key in $regKeys) {
        Get-ItemProperty $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.InstallLocation -and $_.InstallLocation.Trim() } |
            Select-Object DisplayName, InstallLocation
    }

    foreach ($app in ($apps | Sort-Object DisplayName)) {
        $loc = $app.InstallLocation.TrimEnd('\')
        if (-not (Test-Path $loc -ErrorAction SilentlyContinue)) { continue }
        if (Test-ShouldIgnore $loc) { continue }

        $binDir = Join-Path $loc "bin"
        if ((Test-OnPath $loc) -or (Test-OnPath $binDir)) { continue }

        # Check for CLI executables (skip uninstallers, crash handlers, etc.)
        $exes = @(Get-ChildItem $loc -Filter "*.exe" -Depth 0 -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch 'unins|crash|update\.exe$|setup\.exe$' })
        $binExes = @()
        if (Test-Path $binDir) {
            $binExes = @(Get-ChildItem $binDir -Filter "*.exe" -Depth 0 -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch 'unins|crash|update\.exe$|setup\.exe$' })
        }

        if ($exes.Count -eq 0 -and $binExes.Count -eq 0) { continue }

        $bestDir = if ($binExes.Count -gt 0) { $binDir } else { $loc }
        $exeNames = (($exes + $binExes) | Select-Object -ExpandProperty Name -First 5) -join ', '

        $results += [PSCustomObject]@{
            Source      = "Registry"
            Name        = $app.DisplayName
            Directory   = $bestDir
            Executables = $exeNames
        }
        Write-Report ("  {0,-40} {1}" -f $app.DisplayName, $bestDir)
        Write-Report ("  {0,-40} Exes: {1}" -f '', $exeNames) DarkGray
    }

    if (($results | Where-Object Source -eq "Registry").Count -eq 0) {
        Write-Report "  No missing registry apps found." Green
    }
    Write-Report ""
}

# ── 2. npm global scan ─────────────────────────────────────────────────────
if (-not $SkipNpm) {
    Write-Report "--- npm Global Packages ---" Yellow

    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npmCmd) {
        Write-Report "  npm not found on PATH — skipping." DarkGray
    } else {
        $npmPrefix = (npm prefix -g 2>$null)
        if ($npmPrefix) {
            $npmPrefix = $npmPrefix.Trim()
            $onPath = Test-OnPath $npmPrefix

            # List global packages
            $npmList = npm list -g --depth=0 --parseable 2>$null
            $globalPkgs = @()
            if ($npmList) {
                $globalPkgs = $npmList -split "`r?`n" | Where-Object { $_ -and $_ -ne $npmPrefix }
            }

            # Find .cmd shims in the prefix directory
            $shims = @(Get-ChildItem $npmPrefix -Filter "*.cmd" -ErrorAction SilentlyContinue)

            if ($shims.Count -gt 0) {
                if ($onPath) {
                    Write-Report "  npm global prefix ($npmPrefix) is on PATH." Green
                    Write-Report "  $($shims.Count) global command(s): $(($shims.Name -replace '\.cmd$','') -join ', ')" DarkGray
                } else {
                    Write-Report "  MISSING: npm global prefix not on PATH" Red
                    Write-Report "  Directory: $npmPrefix" Red
                    Write-Report "  $($shims.Count) command(s) unreachable: $(($shims.Name -replace '\.cmd$','') -join ', ')" Red

                    $results += [PSCustomObject]@{
                        Source      = "npm-global"
                        Name        = "npm global packages ($($shims.Count) commands)"
                        Directory   = $npmPrefix
                        Executables = ($shims.Name -replace '\.cmd$','') -join ', '
                    }
                }
            } else {
                Write-Report "  No global npm packages with CLI commands found." DarkGray
            }
        }
    }
    Write-Report ""
}

# ── Summary ─────────────────────────────────────────────────────────────────
Write-Report "============================================" Cyan
if ($results.Count -eq 0) {
    Write-Report "  All installed CLI tools are reachable via PATH." Green
} else {
    Write-Report "  $($results.Count) app/package group(s) missing from PATH." Red
}
Write-Report "============================================" Cyan

return $results
