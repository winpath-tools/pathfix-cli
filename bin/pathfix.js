#!/usr/bin/env node
"use strict";

const { execFileSync } = require("child_process");
const path = require("path");

if (process.platform !== "win32") {
  console.error("pathfix only runs on Windows.");
  process.exit(1);
}

const SCRIPTS_DIR = path.join(__dirname, "..", "scripts");

// Each flag maps to { ps: "<PowerShell param>", isSwitch: <bool> }.
// isSwitch: true  → passed as a bare switch (-FlagName)
// isSwitch: false → expects a following value (-Param Value)
const COMMANDS = {
  diagnose: {
    script: "Diagnose-Path.ps1",
    desc: "Check PATH for duplicates, missing dirs, stale entries, and tool reachability",
    flags: {
      "--auto-restore": { ps: "-AutoRestore", isSwitch: true },
    },
  },
  backup: {
    script: "Backup-Path.ps1",
    desc: "Backup System and User PATH to OneDrive (timestamped)",
    flags: {
      "--skip-audit": { ps: "-SkipAudit", isSwitch: true },
      "--dir":        { ps: "-BackupDir",  isSwitch: false },
      "--max":        { ps: "-MaxBackups", isSwitch: false },
    },
  },
  restore: {
    script: "Restore-Path.ps1",
    desc: "Restore PATH from a backup file",
    flags: {
      "--scope": { ps: "-Scope",     isSwitch: false },
      "--dir":   { ps: "-BackupDir", isSwitch: false },
    },
  },
  audit: {
    script: "Audit-PathApps.ps1",
    desc: "Scan registry installs and npm globals for CLI tools missing from PATH",
    flags: {
      "--skip-registry": { ps: "-SkipRegistry", isSwitch: true },
      "--skip-npm":      { ps: "-SkipNpm",      isSwitch: true },
      "--quiet":         { ps: "-Quiet",         isSwitch: true },
    },
  },
};

function printUsage() {
  console.log("");
  console.log("  pathfix <command> [options]");
  console.log("");
  console.log("  Commands:");
  for (const [name, cmd] of Object.entries(COMMANDS)) {
    console.log(`    ${name.padEnd(12)} ${cmd.desc}`);
  }
  console.log("");
  console.log("  Options per command:");
  for (const [name, cmd] of Object.entries(COMMANDS)) {
    const flags = Object.keys(cmd.flags);
    if (flags.length) {
      console.log(`    ${name}: ${flags.join(", ")}`);
    }
  }
  console.log("");
  console.log("  Examples:");
  console.log("    pathfix diagnose");
  console.log("    pathfix backup --skip-audit");
  console.log("    pathfix restore --scope User");
  console.log("    pathfix audit --skip-npm");
  console.log("");
}

function buildPwshArgs(command, argv) {
  const scriptPath = path.join(SCRIPTS_DIR, command.script);
  const psArgs = [
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", scriptPath,
  ];

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const flagDef = command.flags[arg];

    if (!flagDef) {
      console.error(`Unknown flag: ${arg}`);
      process.exit(1);
    }

    if (flagDef.isSwitch) {
      psArgs.push(flagDef.ps);
    } else {
      const value = argv[++i];
      if (!value || value.startsWith("--")) {
        console.error(`Flag ${arg} requires a value`);
        process.exit(1);
      }
      psArgs.push(flagDef.ps, value);
    }
  }

  return psArgs;
}

// ── Main ────────────────────────────────────────────────────────────────────
const [commandName, ...rest] = process.argv.slice(2);

if (!commandName || commandName === "--help" || commandName === "-h") {
  printUsage();
  process.exit(0);
}

const command = COMMANDS[commandName];
if (!command) {
  console.error(`Unknown command: ${commandName}`);
  printUsage();
  process.exit(1);
}

const psArgs = buildPwshArgs(command, rest);

try {
  execFileSync("pwsh", psArgs, { stdio: "inherit", windowsHide: true });
} catch (err) {
  // pwsh not found — fall back to Windows PowerShell
  if (err.code === "ENOENT") {
    try {
      execFileSync("powershell", psArgs, { stdio: "inherit", windowsHide: true });
    } catch (innerErr) {
      process.exit(innerErr.status || 1);
    }
  } else {
    process.exit(err.status || 1);
  }
}
