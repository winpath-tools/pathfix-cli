#!/usr/bin/env node
"use strict";

const { execFileSync } = require("child_process");
const path = require("path");

const SCRIPTS_DIR = path.join(__dirname, "..", "scripts");

const COMMANDS = {
  diagnose: {
    script: "Diagnose-Path.ps1",
    desc: "Check PATH for duplicates, missing dirs, stale entries, and tool reachability",
    flags: { "--auto-restore": "-AutoRestore" },
  },
  backup: {
    script: "Backup-Path.ps1",
    desc: "Backup System and User PATH to OneDrive (timestamped)",
    flags: {
      "--skip-audit": "-SkipAudit",
      "--dir": "-BackupDir",
      "--max": "-MaxBackups",
    },
  },
  restore: {
    script: "Restore-Path.ps1",
    desc: "Restore PATH from a backup file",
    flags: {
      "--scope": "-Scope",
      "--dir": "-BackupDir",
    },
  },
  audit: {
    script: "Audit-PathApps.ps1",
    desc: "Scan registry installs and npm globals for CLI tools missing from PATH",
    flags: {
      "--skip-registry": "-SkipRegistry",
      "--skip-npm": "-SkipNpm",
      "--quiet": "-Quiet",
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
    const psFlag = command.flags[arg];

    if (!psFlag) {
      console.error(`Unknown flag: ${arg}`);
      process.exit(1);
    }

    // Check if this flag takes a value (doesn't start with "-" as a switch)
    // Switch params in PS are just -FlagName; value params need -Param Value
    const isSwitch = ["-AutoRestore", "-SkipAudit", "-SkipRegistry", "-SkipNpm", "-Quiet"].includes(psFlag);

    if (isSwitch) {
      psArgs.push(psFlag);
    } else {
      const value = argv[++i];
      if (!value) {
        console.error(`Flag ${arg} requires a value`);
        process.exit(1);
      }
      psArgs.push(psFlag, value);
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
