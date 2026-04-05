# pathfix-cli

Windows PATH diagnostic, backup, restore, and audit tools — packaged as a global npm CLI.

## Why

Windows PATH corruption is surprisingly common: duplicate entries, System and User PATH merging, stale references to uninstalled tools, missing entries for CLI tools that should be reachable. `pathfix` catches and fixes these issues.

## Install

```
npm install -g github:winpath-tools/pathfix-cli
```

Requires **Node.js >= 18** and **PowerShell 7+** (`pwsh`) on Windows.

## Commands

| Command | Description |
|---------|-------------|
| `pathfix diagnose` | Check PATH for duplicates, missing dirs, stale entries, and tool reachability |
| `pathfix backup` | Backup System and User PATH to timestamped files |
| `pathfix restore` | Interactively restore PATH from a backup |
| `pathfix audit` | Scan registry and npm globals for CLI tools missing from PATH |

### diagnose

```
pathfix diagnose [--auto-restore]
```

Runs six checks:
1. Empty entries
2. System PATH internal duplicates
3. User PATH internal duplicates
4. Cross-duplicates (User entries already in System)
5. Non-existent paths
6. Well-known tool reachability (winget, git, node, python, dotnet, code, pwsh, choco)

Also syncs the current session's `$env:Path` with the registry if they've diverged.

### backup

```
pathfix backup [--skip-audit] [--dir <path>] [--max <n>]
```

- Saves System and User PATH to timestamped `.txt` files
- Auto-prunes old backups beyond `--max` (default: 20)
- Runs an installed-apps audit after backup (skip with `--skip-audit`)
- Default backup dir: `$env:OneDrive\PATH_Backups` (falls back to `$env:USERPROFILE`)

### restore

```
pathfix restore [--scope System|User|Both] [--dir <path>]
```

- Lists available backups sorted by date
- Preview before applying
- Creates an automatic pre-restore backup
- Requires elevation for System PATH restore
- Refreshes the current session PATH after restore

### audit

```
pathfix audit [--skip-registry] [--skip-npm] [--quiet]
```

- Scans Windows registry (HKLM/HKCU uninstall keys) for installed apps with CLI executables not on PATH
- Checks npm global prefix for unreachable commands
- Filters out games, GPU drivers, browsers, and GUI-only apps automatically

## How it works

A thin Node.js CLI wrapper (`bin/pathfix.js`) dispatches to bundled PowerShell scripts via `pwsh`. PowerShell is used because Windows PATH manipulation requires native APIs (`[Environment]::SetEnvironmentVariable`, registry access, `Test-Path`).

## License

[MIT](LICENSE)
