# Security Policy

## Scope

pathfix-cli modifies Windows PATH environment variables at the **Machine** (System) and **User** scope. The `restore` and `backup` commands can write to the registry and the file system. The `diagnose --auto-restore` flag can trigger a restore without interactive confirmation.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.x     | Yes       |

## Reporting a Vulnerability

If you discover a security issue, please **do not** open a public GitHub issue.

Instead, email the maintainers or use [GitHub's private vulnerability reporting](https://github.com/winpath-tools/pathfix-cli/security/advisories/new).

We will acknowledge receipt within 72 hours and aim to release a fix within 7 days for critical issues.

## Security Considerations

- **Elevation**: Restoring or modifying System PATH requires running as Administrator. The scripts check for elevation before attempting writes.
- **Execution Policy**: The CLI invokes PowerShell with `-ExecutionPolicy Bypass` scoped to the process — it does not change the system-wide execution policy.
- **Backup files**: PATH backups are stored as plain text. They do not contain secrets, but they do reveal installed software paths. Store backups in a location with appropriate access controls.
- **No network access**: None of the scripts make network calls. All operations are local.
