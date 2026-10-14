# AGENTS.md

Instructions for AI coding agents (Grok, Claude Code, Copilot, Codex, Cursor). Humans: see README.md.

## Workflow
Follow the `engineering-flow` skill (shared hub: `C:\Repos\Scripts\.agents\skills`): grill-me -> write-spec -> write-plan -> worktree/branch -> tdd -> verify -> PR -> pr-review-loop -> merge -> log.
Branches: `lundgren-greg/<name>` in `C:\Users\lundg\orca\workspaces\pathfix-cli\<name>`. Specs: `docs/specs/`. Plans: `docs/plans/`.
`main` requires the "Lint & Validate" CI check and linear history; all changes go through PRs (squash merge).

## Project
`pathfix` is a zero-dependency Node.js (>=18) CLI that wraps four PowerShell 7 scripts for Windows PATH diagnose / backup / restore / audit. Windows only.

## Commands (mirror CI in `.github/workflows/ci.yml`)
- Entry point parses: `node -c bin/pathfix.js`
- Help smoke test: `node bin/pathfix.js --help`
- PowerShell syntax: parse `scripts/*.ps1` with `[System.Management.Automation.Language.Parser]::ParseFile`
- Lint: `Invoke-ScriptAnalyzer -Path scripts -Severity Error`
- Smoke: `pwsh -NoProfile -File scripts/Diagnose-Path.ps1` (read-only)

## Layout
- `bin/pathfix.js` — sole entry point; flag mapping in `COMMANDS`, switch vs value params in `buildPwshArgs()`
- `scripts/*.ps1` — one script per command (`[CmdletBinding()]`, Verb-Noun)
- `.github/copilot-instructions.md` — detailed conventions and "adding a command" checklist (applies to all agents)

## Conventions
- JS: CommonJS, `"use strict"`, 2-space, LF. PowerShell: 4-space, approved verbs. No npm dependencies.
- `restore` overwrites the real machine/user PATH: never run `Restore-Path.ps1` in tests or CI (a test backup does not make it safe).
- `backup` writes and prunes files in `$env:OneDrive\PATH_Backups` by default: in tests always pass `-BackupDir` pointing at a temp dir.
- Never commit secrets or real PATH backups; quarantine anything sensitive and report it.
- Record lasting changes in README.md or the wiki.
