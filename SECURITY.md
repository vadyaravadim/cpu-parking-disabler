# Security Policy

## Reporting a Vulnerability

Please report security issues **privately** via
[GitHub Security Advisories](https://github.com/vadyaravadim/cpu-parking-disabler/security/advisories/new)
— not through a public issue.

Expect a first response within 7 days. If a fix is warranted, it ships as a new
tagged release and the advisory is published once the fix is available.

## Supported Versions

Only the latest release receives fixes. Older tags are left as-is — update to the
newest version before reporting.

## Scope

This script runs **with administrator rights** and modifies the active Windows
power scheme via `powercfg`. That is its intended purpose, not a vulnerability.

In scope:

- The self-elevation path (`irm | iex` saving to `%USERPROFILE%` and re-running
  from there) — e.g. a way to make it execute attacker-controlled content
- The saved-copy / `.bak` handling — e.g. a path that overwrites an unrelated file
- The release pipeline — checksums, provenance, or the PowerShell Gallery package
  not matching the tagged source

Out of scope:

- Requiring admin rights, or the UAC prompt
- Higher idle power draw and temperatures — documented in
  [Side Effects](README.md#side-effects)
- Changes persisting across reboots — documented in the
  [FAQ](README.md#do-the-changes-survive-a-reboot), and reversible per
  [Rollback](README.md#rollback)
- Running an unmodified `.pow` backup or power scheme into an unwanted state

## Verifying a Release

Each release publishes `SHA256SUMS.txt` and Sigstore build provenance. Verify a
download before running it:

```powershell
Get-FileHash .\cpu-parking-disabler.ps1 -Algorithm SHA256
```

Compare the hash against the one in the corresponding
[release](https://github.com/vadyaravadim/cpu-parking-disabler/releases).
