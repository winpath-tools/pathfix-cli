# Copilot Instructions for pathfix-cli

## Project overview

`@winpath-tools/pathfix-cli` is a Node.js CLI (`pathfix`) that wraps four PowerShell scripts for Windows PATH management:

| Command            | Script                 | Purpose                                              |
| ------------------ | ---------------------- | ---------------------------------------------------- |
| `pathfix diagnose` | `Diagnose-Path.ps1`   | Check PATH for duplicates, missing dirs, stale entries |
| `pathfix backup`   | `Backup-Path.ps1`     | Backup System and User PATH (timestamped)            |
| `pathfix restore`  | `Restore-Path.ps1`    | Restore PATH from a backup file                      |
| `pathfix audit`    | `Audit-PathApps.ps1`  | Scan for CLI tools missing from PATH                 |

Entry point: `bin/pathfix.js` — uses `child_process.execFileSync` to invoke `pwsh`.

## Tech stack

- **Runtime**: Node.js >= 18 (no dependencies — stdlib only)
- **Scripts**: PowerShell 7+ (`pwsh`), Windows-only
- **CI**: GitHub Actions on `windows-latest` (PSScriptAnalyzer, node syntax, smoke test)
- **OS**: Windows only (`"os": ["win32"]` in package.json)

## Code conventions

- JavaScript: CommonJS (`require`), `"use strict"`, 2-space indent, LF line endings
- PowerShell: 4-space indent, approved verbs (`Verb-Noun`), `[CmdletBinding()]` on all scripts
- EditorConfig enforced (see `.editorconfig`)
- No external npm dependencies — keep it zero-dep

## Architecture rules

- `bin/pathfix.js` is the sole entry point; it maps CLI flags to PowerShell parameters
- Each command maps to exactly one `.ps1` script in `scripts/`
- Flag mapping is defined in the `COMMANDS` object — add new flags there
- Switch parameters (boolean) vs value parameters are distinguished in `buildPwshArgs()`

## Branch protection

- `main` requires passing CI check "Lint & Validate" and linear history
- All changes go through PRs

## When adding a new command

1. Add the `.ps1` script to `scripts/`
2. Add the command entry to `COMMANDS` in `bin/pathfix.js`
3. Update `README.md` with usage info
4. Ensure the script has `[CmdletBinding()]` and follows existing parameter patterns
